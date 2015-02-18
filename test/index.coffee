_ = require('lodash')
Chance = require('chance')
ElasticSearchClient = require('elasticsearchclient')
expect = require('chai').expect
url = require('url')
TaskIndexConsultant = require('../')

chance = new Chance()

# This function is boilerplate for replicating how Amazon Kinesis events are
# passed to Lambda for processing.
#
# payloadString - The String to package
#
# Returns an Object as the data would be passed to Lambda
packageEvent = (payloadString) ->
  encodedPayload = new Buffer(payloadString).toString('base64')

  'Records': [
    'kinesis':
      'partitionKey': 'partitionKey-3'
      'kinesisSchemaVersion': '1.0'
      'data': encodedPayload
      'sequenceNumber': '495451152444582180062593244200961'
    'eventSource': 'aws:kinesis'
    'eventID': 'shardId-000000000000:495451152473144582180062593244200961'
    'invokeIdentityArn': 'arn:aws:iam::059493405231:role/testLEBRole'
    'eventVersion': '1.0'
    'eventName': 'aws:kinesis:record'
    'eventSourceARN': 'arn:aws:kinesis:us-east-1:12example:stream/examplestream'
    'awsRegion': 'us-east-1'
  ]

# This object is boilerplate for the context passed to an Amazon Lambda
# function. Calling done() exits the process Lambda creates.
context =
  done: (error, message) ->
    console.log 'done!'
    process.exit 1

# Create connection to Elastic Search client
connectionString = url.parse process.env.SEARCHBOX_URL
serverOptions =
  host: connectionString.hostname,
  port: 80,
  secure: false
  auth:
    username: connectionString.auth.split(':')[0]
    password: connectionString.auth.split(':')[1]
client = new ElasticSearchClient(serverOptions)

delayedSearch = (name, callback) ->
  _.delay performSearch, 1000, name, callback

performSearch = (name, callback) ->
  qryObj =
    query:
      bool:
        must: [
          query_string:
            fields: ['name']
            query: name
        ]
    size: 1000
  client
    .search(process.env.SEARCHLY_INDEX_CONSULTANTS, 'document', qryObj)
    .on 'data', (data) ->
      hits = JSON.parse(data)?.hits?.hits
      # Return an Array of results
      callback null, _.map JSON.parse(data)?.hits?.hits, (hit) ->
        id: hit._id
        score: hit._score
    .on 'error', (err) ->
      callback err, null
    .exec()

describe 'TaskIndexConsultant', ->

  @timeout(10000)
  it 'should ignore irrelevant events', (done) ->

    testId = chance.hash()
    testName = chance.name({middle: true})

    otherEvent = packageEvent JSON.stringify
      eventName: 'some-other-event'
      document:
        id: testId
        displayFullName: testName

    testContext =
      done: ->
        delayedSearch testName, (err, results) ->
          expect(_.pluck results, 'id').to.not.include(testId)
          done()

    TaskIndexConsultant.handler otherEvent, testContext

  it 'should ignore companies', (done) ->

    testId = chance.hash()
    testName = chance.name({middle: true})

    companyEvent = packageEvent JSON.stringify
      eventName: 'user-create'
      document:
        id: testId
        displayFullName: testName
        accountType: 'COMPANY'

    testContext =
      done: ->
        delayedSearch testName, (err, results) ->
          expect(_.pluck results, 'id').to.not.include(testId)
          done()

    TaskIndexConsultant.handler companyEvent, testContext

  it 'should index newly created users', (done) ->

    testId = chance.guid()
    testName = chance.name({middle: true})

    createEvent = packageEvent JSON.stringify
      eventName: 'user-create'
      document:
        id: testId
        displayFullName: testName

    testContext =
      done: ->
        delayedSearch testName, (err, results) ->
          expect(_.pluck results, 'id').to.include(testId)
          done()

    TaskIndexConsultant.handler createEvent, testContext

  it 'should index updated users', (done) ->

    testId = chance.guid()
    testName = chance.name({middle: true})

    updateEvent = packageEvent JSON.stringify
      eventName: 'user-update'
      document:
        id: testId
        displayFullName: testName

    testContext =
      done: ->
        delayedSearch testName, (err, results) ->
          expect(_.pluck results, 'id').to.include(testId)
          done()

    TaskIndexConsultant.handler updateEvent, testContext

  it 'should remove deleted users', (done) ->

    testId = chance.guid()
    testName = chance.name({middle: true})

    createEvent = packageEvent JSON.stringify
      eventName: 'user-create'
      document:
        id: testId
        displayFullName: testName

    deleteEvent = packageEvent JSON.stringify
      eventName: 'user-delete'
      document:
        id: testId
        displayFullName: testName

    firstTestContext =
      done: ->
        delayedSearch testName, (err, results) ->
          expect(_.pluck results, 'id').to.include(testId)
          TaskIndexConsultant.handler deleteEvent, secondTestContext

    secondTestContext =
      done: ->
        delayedSearch testName, (err, results) ->
          expect(_.pluck results, 'id').to.not.include(testId)
          done()

    TaskIndexConsultant.handler createEvent, firstTestContext
