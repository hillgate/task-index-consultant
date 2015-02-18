_ = require('lodash')
argv = require('yargs').argv
AWS = require('aws-sdk')
coffee = require('gulp-coffee')
del = require('del')
dotenv = require('dotenv')
fs = require('fs')
gulp = require('gulp')
gulpif = require('gulp-if')
gutil = require('gulp-util')
install = require('gulp-install')
replace = require('gulp-replace')
runSequence = require('run-sequence')
zip = require('gulp-zip')

# Store AWS credentials in .env.development if you like.
process.env.NODE_ENV = 'development'
dotenv.load()

distDir = 'dist'

# First we need to clean out the dist folder and remove the compiled zip file.
gulp.task 'clean', (cb) ->
  del "./#{distDir}", del("./#{distDir}.zip", cb)

# The js task could be replaced with gulp-coffee as desired.
gulp.task 'js', ->
  gulp.src('index.coffee')
    .pipe(gulpif(
      argv.production,
      replace("NODE_ENV = 'development'", "NODE_ENV = 'production'")
    ))
    .pipe(coffee())
    .pipe(gulp.dest(distDir))

# Here we want to install npm packages to dist, ignoring devDependencies.
gulp.task 'npm', ->
  gulp.src('package.json')
    .pipe(gulp.dest(distDir))
    .pipe(install(production: true))

# Next copy over environment variables managed outside of source control.
gulp.task 'env', ->
  gulp.src([
    '.env*'
    '!.env.development'
    ])
    .pipe(gulp.dest(distDir))

# Now the dist directory is ready to go. Zip it.
gulp.task 'zip', ->
  gulp.src([
    "#{distDir}/**/*"
    "!#{distDir}/package.json"
    "#{distDir}/.*"
  ]).pipe(zip("#{distDir}.zip"))
    .pipe(gulp.dest('./'))

# Per the gulp guidelines, we do not need a plugin for something that can be
# done easily with an existing node module. #CodeOverConfig
#
# Note: This presumes that AWS.config already has credentials. This will be
# the case if you have installed and configured the AWS CLI.
#
# See http://aws.amazon.com/sdk-for-node-js/
gulp.task 'upload', ->

  AWS.config.region = 'us-east-1'
  lambda = new (AWS.Lambda)
  env = if argv.production then 'production' else 'staging'
  functionName = "index-consultant-#{env}"
  lambda.getFunction { FunctionName: functionName }, (err, data) ->
    if err
      if err.statusCode is 404
        gutil.log "Unable to find lambda function #{functionName}.
          Verify the lambda function name and AWS region are correct."
      else
        gutil.log 'AWS API request failed. Check your AWS credentials and
          permissions.'
    else

      # This is a bit silly, simply because these five parameters are required.
      params = _.extend FunctionName: functionName,
        _.pick data.Configuration, 'Handler', 'Mode', 'Role', 'Runtime'

      fs.readFile "./#{distDir}.zip", (err, data) ->
        params['FunctionZip'] = data
        lambda.uploadFunction params, (err, data) ->
          if err
            gutil.log 'Package upload failed.
              Check your iam:PassRole permissions.'

# The key to deploying as a single command is to manage the sequence of events.
gulp.task 'default', (callback) ->
  runSequence [ 'clean' ], [
    'js'
    'npm'
    'env'
  ], 'zip' , 'upload' , callback
