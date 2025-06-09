# Data format for NEURLFilter

Understand the data format that Network Extension URL Filter expects.

## Overview

Network Extension on-device examines all URL requests, checking each URL against a Bloom filter built from your URL data set, containing URLs you want to block.
If the Bloom filter match is negative, the URL is not in your data set and it will be allowed immediately. If the Bloom filter match is positive, the match result is not
definitive due to potential false positives. In this case, an off-device URL query will be sent to your PIR server to match against your URL data set to get a final verdict.
If your PIR server responds with a match, the system on-device will block the URL, and the URL request will fail.

## URL Data Record

The URL data record has the URL (excluding the scheme portion) as the key. For example, for URL `https://www.example.com`, the URL key should be
`www.example.com`. If an entry is found matching the URL key, it already indicates a match. So the value for the record is simply set to the integer 1 serving as place holder.

Value | Description
----- | -----------
1     | <Place holder>
