_ = require('lodash')
async = require('async')
dotenv = require('dotenv')
ElasticSearchClient = require('elasticsearchclient')
url = require('url')

# This function sends user documents to Searchly for indexing.
# It consumes data from Kinesis events for user create/update/delete.

process.env.NODE_ENV = 'development'

# Store sensitive variables in an environment file outside of source control.
dotenv.load()

# Extract data from the kinesis event
exports.handler = (event, context) ->

  # This function abstracts the expected structure of any Kinesis payload,
  # which is a base64-encoded string of a JSON object, passing the data to
  # a private function.
  handlePayload = (record, callback) ->
    encodedPayload = record.kinesis.data
    rawPayload = new Buffer(encodedPayload, 'base64').toString('utf-8')
    handleData JSON.parse(rawPayload), callback

  # The Kinesis event may contain multiple records in a specific order.
  # But in the case of our consultant index, we do not need to maintain strict
  # order. `async.each` is fine.
  async.each event.Records, handlePayload, context.done

# This is how we do it…
handleData = (data, callback) ->

  # Because we're subscribing to a stream that contains events, we need to
  # check event name after decoding the payload.
  switch data.eventName
    when 'user-create', 'user-update'
      indexConsultant(data.document, callback)
    when 'user-delete'
      removeConsultant(data.document, callback)
    else
      callback()

indexConsultant = (consultant, callback) ->
  return callback() if consultant.accountType is 'COMPANY'
  getClient().index(
    process.env.SEARCHLY_INDEX_CONSULTANTS
    'document'
    buildIndex(consultant)
    consultant.id
  ).on('data', (data) ->
    console.log "Consultant indexed: #{consultant.id}"
    console.log data
    callback null, data
  ).on('error', (err) ->
    console.log "ERROR: Consultant index #{consultant.id}"
    console.log err
    callback err, null
  ).exec()

removeConsultant = (consultant, callback) ->
  return callback() if consultant.accountType is 'COMPANY'
  qryObj =
    query:
      bool:
        must: [
          query_string:
            fields: ['_id']
            query: consultant.id
        ]
  getClient().deleteByQuery(
    process.env.SEARCHLY_INDEX_CONSULTANTS
    'document'
    qryObj
  ).on('data', (data) ->
    console.log "Consultant deleted: #{consultant.id}"
    console.log data
    callback null, data
  ).on('error', (err) ->
    console.log "ERROR: Consultant delete #{consultant.id}"
    console.log err
    callback err, null
  ).exec()

getClient = ->
  connectionString = url.parse process.env.SEARCHBOX_URL
  serverOptions =
    host: connectionString.hostname,
    port: 80,
    secure: false
    auth:
      username: connectionString.auth.split(':')[0]
      password: connectionString.auth.split(':')[1]
  new ElasticSearchClient(serverOptions)

# Parses consultant data into a document format suitable for indexing
buildIndex = (consultant) ->
  _.merge _.pick(consultant, ['summary','languages','functionalAreas']),
    _id: consultant.id
    name: consultant.displayFullName
    location: consultant.location?.name
    headline: "#{consultant.headline} #{consultant.linkedin?.headline}"
    schools: consultant.schools + consultant.businessSchool?
    industry: getIndexIndustries(consultant)
    skills: getIndexSkills(consultant)
    experience: _.map consultant.linkedin?.positions?.values, (position) ->
      "#{position.title} #{position.company.name} #{position.summary}"
    projects: _.map consultant.projects, (project) ->
      "#{project.summary} #{project.industry} #{project.location}"

getIndexIndustries = (consultant) ->
  industries = consultant.industries + consultant.industry
  _.union industries, _.map consultant.projects, (project) ->
    project.industry

getIndexSkills = (consultant) ->
  skills = _.map consultant.linkedin?.skills?.values, (skill) ->
    skill.skill?.name
  _.union skills, _.flatten _.map consultant.projects, (project) ->
    project.skills
