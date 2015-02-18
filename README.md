## Summary

This task is written as:

1. an Amazon Lambda function
2. designed to consume Kinesis events
3. to index consultants using Searchly

## Required Environment Variables

* SEARCHBOX_URL
* SEARCHLY_INDEX_CONSULTANTS

## Inputs

* consultant — an Object containing the JSON representation of a consultant

The function should subscribe to the following events:

    user-created
    user-updated
    user-deleted
