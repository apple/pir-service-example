# ``PIRService``

Example service for Live Caller ID Lookup and NEURLFilter

## Overview

This service is a non-scalable example that can be used to test both Live Caller ID Lookup and NEURLFilter features. Please see
<doc:TestingInstructionsLiveCallerIdLookup> and <doc:TestingInstructionsNEURLFilter> to see instructions on how to run the example service and connect your phone to the service.

### Live Caller ID Lookup

[Live Caller ID
Lookup](https://developer.apple.com/documentation/sms_and_call_reporting/getting_up-to-date_calling_and_blocking_information_for_your_app)
is a new feature in iOS 18.0 that allows the system to communicate with a third party service to privately retrieve information
about a phone number for an incoming call. This allows the system to automatically block known spam callers and display
identity information on the incoming call screen.

![Live Caller ID Lookup data flow diagram](overview.png)

### NEURLFilter

[NEURLFilter](https://developer.apple.com/documentation/networkextension/neurlfiltermanager) is a new feature for iOS and MacOS that allows the system
to communicate with a third party service to privately check if a requested URL should be allowed or not. This allows your app to implement URL filtering in a privacy preserving manner.

## Topics
