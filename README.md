## Summary

This task is written as:

1. an Amazon Lambda function
2. designed to consume Kinesis events
3. to index consultants using Searchly

## Required environment variables

* SEARCHBOX_URL — A String with the endpoint url including basic auth
* SEARCHLY_INDEX_CONSULTANTS — a String identifying the Searchly index to use

## Inputs within decoded Kinesis payload

* eventName — a String
* document — an Object containing the JSON representation of a consultant

The function is built to subscribes to the following event names:

    user-created
    user-updated
    user-deleted

## Development

To run tests once using Mocha:

    npm test

To run tests continuously using Mocha and Testem

    npm run

## Deployment

To deploy to staging:

    gulp

To deploy to production:

    gulp --production

## Live testing with on AWS Console

After you run the test suite, the test folder will be populated with json files
representing the data sent through each test. The AWS Lambda console allows you
to test out the functionality using data you have copied in, and these files
will be a suitable format for testing.
