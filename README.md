# KTBTaskQueue

[![Build Status](https://travis-ci.org/kevboh/KTBTaskQueue.png?branch=master)](https://travis-ci.org/kevboh/KTBTaskQueue)
[![Version](http://cocoapod-badges.herokuapp.com/v/KTBTaskQueue/badge.png)](http://cocoadocs.org/docsets/KTBTaskQueue)
[![Platform](http://cocoapod-badges.herokuapp.com/p/KTBTaskQueue/badge.png)](http://cocoadocs.org/docsets/KTBTaskQueue)

`KTBTaskQueue` is an optionally persistent queue that makes sure tasks get finished. It will prompt a delegate or block with a task until that task is declared successful or abandoned. Failed tasks can be retried immediately or at some point in the future, with the default following an exponential backoff pattern. The basic flow goes like this:

1. Put a task in the queue.
2. The queue hands the task to its delegate or an execution block. Whatever is executing the task... executes the task. You decide what executing a task looks like.
3. If the task is successful it's removed from the queue. If not, it's kept around and retried until it succeeds or it reaches a `maxRetries` threshhold, after which it is abandonded and removed from the queue.

`KTBTaskQueue` can be used to track any task you wish. I find it useful to make sure network requests are successful when online and to keep them for later when offline.

## Using It

KTBTaskQueue is available through [CocoaPods](http://cocoapods.org), to install
it simply add the following line to your Podfile:

    pod "KTBTaskQueue"

Then in code, let’s say you use [AFNetworking](https://github.com/AFNetworking/AFNetworking) and want to make sure a particularly important POST reaches your server. You could do something like:

    // You created this queue in your app delegate or view controller or model.
    [self.queue enqueueTaskWithName:@"PostThisVitalThing" userInfo:@{"wow" : "so important"}];

Okay, now the queue will bug its delegate until the `PostThisVitalThing` task is complete. In the delegate:

    - (void)taskQueue:(KTBTaskQueue *)queue executeTask:(KTBTask *)task completion:(KTBTaskCompletionBlock)completion {
        // The task's userInfo is this request's parameters
        AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
        [manager POST:@"http://example.com/resources.json" parameters:task.userInfo success:^(AFHTTPRequestOperation *operation, id responseObject) {
            NSLog(@"JSON: %@", responseObject);
            completion(KTBTaskStatusSuccess);
        } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
            NSLog(@"Error: %@", error);
            completion(KTBTaskStatusFailure);
        }];
    }

By default, `PostThisVitalThing` will be retried after failure up to 10 times. That number can be customized, along with tons of other aspects of a task, by using a longer constructor available through `KTBTask`:

    [self.queue enqueueTask:[KTBTask taskWithName:@"FutureTask"
                                         userInfo:nil
                                    availableDate:[NSDate dateWithTimeIntervalSinceNow:60]
                                       maxRetries:3
                                       useBackoff:NO]];

`FutureTask` won't be attempted until a minute from now, will only be retried 3 times (for a total of four attempts), and will be retried immediately upon failure—the queue won't delay retry using its backoff technique.

The `KTBTaskQueueDelegate` offers more flexibility. It includes optional methods to report when tasks are abandoned and allows a custom delay to be applied in place of the built-in backoff delay. Check out `KTBTaskQueue.h` and `KTBTaskQueueDelegate.h` for more details and things to play with.

There's also an `executionBlock` property on `KTBTaskQueue` if you hate the delegate pattern:

    // Set the block that does the task
    queue.executionBlock = ^(KTBTask *task, KTBTaskCompletionBlock completion) {
        // The task's userInfo is this request's parameters
        AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
        [manager POST:@"http://example.com/resources.json" parameters:task.userInfo success:^(AFHTTPRequestOperation *operation, id responseObject) {
            NSLog(@"JSON: %@", responseObject);
            completion(KTBTaskStatusSuccess);
        } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
            NSLog(@"Error: %@", error);
            completion(KTBTaskStatusFailure);
        }];
    };
    // Enqueue the task
    [self.queue enqueueTaskWithName:@"PostThisVitalThing" userInfo:@{"wow" : "so important"}];

Also worth mentioning is the `KTBTaskAlwaysRetry` value, which will prevent a queue from abandoning a task due to too many retries:

    [self.queue enqueueTask:[KTBTask taskWithName:@"IReallyWantThisDone"
                                         userInfo:nil
                                    availableDate:nil
                                       maxRetries:KTBTaskAlwaysRetry
                                       useBackoff:YES]];

This task is available immediately (`availableDate` defaults to now) and will retry until it succeeds or the Earth is dust (or you drop your phone in the toilet). Whichever comes first.

## Requirements

ARC, iOS 6+, and [FMDB](https://github.com/ccgus/fmdb) by Gus Mueller. FMDB will be imported automatically by Cocoapods. Don't worry; it's super-small.

## Feedback

Please feel free to open issues and submit pull requests here. Thanks!

## Author

Kevin Barrett, kevin@littlespindle.com

If this helps you out or you think it's neat, check out the app that inspired it: http://airendipity.com.

## License

KTBTaskQueue is available under the MIT license. See the LICENSE file for more info.

