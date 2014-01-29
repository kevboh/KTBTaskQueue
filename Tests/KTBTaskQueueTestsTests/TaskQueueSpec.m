//
//  TaskQueueSpec.m
//  KTBTaskQueue
//
//  Created by Kevin Barrett on 1/25/14.
//  Copyright (c) 2014 Little Spindle, LLC. All rights reserved.
//

#import <Kiwi/Kiwi.h>
#import <KTBTaskQueue/KTBTaskQueue.h>
#import "TaskQueueSpecDelegate.h"
#import "TaskQueueSpecFullDelegate.h"

@interface KTBTaskQueue (TestAdditions)
- (NSString *)pathToDatabase;
- (NSTimer *)pollingTimer;
@end

SPEC_BEGIN(TaskQueueSpec)

describe(@"KTBTaskQueue", ^{
    context(@"when persistent", ^{
        it(@"is backed by a sqlite database", ^{
            NSString *path = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask,YES) objectAtIndex:0] stringByAppendingPathComponent:@"test_queue.mydb"];
            KTBTaskQueue *queue = [KTBTaskQueue queueAtPath:path];
            
            // Check that database exists
            NSFileManager *fileManager = [NSFileManager new];
            BOOL exists = [fileManager fileExistsAtPath:path];
            [[theValue(exists) should] beYes];
            
            [queue deleteQueue];
            
            // Check that the database is gone
            exists = [fileManager fileExistsAtPath:path];
            [[theValue(exists) should] beNo];
        });
        
        it(@"uses the .db file extension", ^{
            NSString *path = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask,YES) objectAtIndex:0] stringByAppendingPathComponent:@"test_queue"];
            KTBTaskQueue *queue = [KTBTaskQueue queueAtPath:path];
            
            // Check that path was affixed with ".db"
            path = [path stringByAppendingString:@".db"];
            [[[queue pathToDatabase] should] equal:path];
            [queue deleteQueue];
        });
    });
    
    context(@"when in memory", ^{
        it(@"should not be on disk", ^{
            KTBTaskQueue *queue = [KTBTaskQueue queueInMemory];
            [[[queue pathToDatabase] should] beNil];
            [queue deleteQueue];
        });
    });
    
    context(@"with an execution block", ^{
        // TODO: replace with let when Kiwi's podspec is updated
        __block KTBTaskQueue *queue = nil;
        beforeEach(^{
            queue = [KTBTaskQueue queueInMemory];
        });
        afterEach(^{
            [queue deleteQueue];
            queue = nil;
        });
        
        it(@"allows task execution", ^{
            __block BOOL didExecute = NO;
            queue.executionBlock = ^(KTBTask *task, KTBTaskCompletionBlock completion) {
                didExecute = YES;
                completion(KTBTaskStatusSuccess);
            };
            
            // Enqueue the task
            [queue enqueueTaskWithName:@"ATask" userInfo:nil];
            
            // Queue should contain it after being added
            [[theValue(didExecute) should] beNo];
            [[theValue([queue containsTaskWithName:@"ATask"]) should] beYes];
            
            // Queue shouldn't contain it after execution
            [[expectFutureValue(theValue(didExecute)) shouldEventually] beYes];
            [[expectFutureValue(theValue([queue containsTaskWithName:@"ATask"])) shouldEventually] beNo];
        });
        
        it(@"supplies userInfo data during execution", ^{
            __block NSDictionary *userInfo = nil;
            queue.executionBlock = ^(KTBTask *task, KTBTaskCompletionBlock completion) {
                userInfo = task.userInfo;
                completion(KTBTaskStatusSuccess);
            };
            
            // Enqueue the task
            NSDictionary *expectedUserInfo = @{
                                               @"MyData": @"IsImportant!",
                                               @"SoIsThis": @2
                                               };
            [queue enqueueTaskWithName:@"ATask" userInfo:expectedUserInfo];
            
            [[expectFutureValue(userInfo) shouldEventually] equal:expectedUserInfo];
        });
        
        it(@"retries failed tasks", ^{
            __block NSUInteger attemptsCount = 0;
            queue.executionBlock = ^(KTBTask *task, KTBTaskCompletionBlock completion) {
                attemptsCount++;
                if (attemptsCount < 3) {
                    completion(KTBTaskStatusFailure);
                }
                else {
                    completion(KTBTaskStatusSuccess);
                }
            };
            
            // Enqueue the task
            [queue enqueueTask:[KTBTask taskWithName:@"FailingTask"
                                            userInfo:nil
                                       availableDate:nil
                                          maxRetries:3
                                          useBackoff:NO]];
            
            [[expectFutureValue(theValue(attemptsCount)) shouldEventuallyBeforeTimingOutAfter(10)] equal:theValue(3)];
        });
        
        it(@"retries failed tasks with backoff", ^{
            __block NSUInteger attemptsCount = 0;
            __block NSDate *lastExecutionDate = nil;
            NSDate *testStartDate = [NSDate date];
            queue.executionBlock = ^(KTBTask *task, KTBTaskCompletionBlock completion) {
                attemptsCount++;
                lastExecutionDate = [NSDate date];
                if (attemptsCount < 3) {
                    completion(KTBTaskStatusFailure);
                }
                else {
                    completion(KTBTaskStatusSuccess);
                }
            };
            
            // Enqueue the task
            [queue enqueueTaskWithName:@"FailingTask" userInfo:nil];
            
            [[expectFutureValue(theValue(attemptsCount)) shouldEventuallyBeforeTimingOutAfter(60)] equal:theValue(3)];
            [[expectFutureValue(theValue([lastExecutionDate timeIntervalSinceDate:testStartDate] > queue.backoffPollingInterval)) should] beYes];
        });
        
        it(@"doesn't retry abandoned tasks", ^{
            __block NSUInteger attemptsCount = 0;
            queue.executionBlock = ^(KTBTask *task, KTBTaskCompletionBlock completion) {
                attemptsCount++;
                completion(KTBTaskStatusAbandon);
            };
            
            // Enqueue the task
            [queue enqueueTaskWithName:@"AbandonedTask" userInfo:nil];
            
            [[expectFutureValue(theValue(attemptsCount)) shouldEventually] equal:theValue(1)];
        });
        
        it(@"abandons tasks after a number of retries", ^{
            __block NSUInteger attemptsCount = 0;
            queue.executionBlock = ^(KTBTask *task, KTBTaskCompletionBlock completion) {
                attemptsCount++;
                completion(KTBTaskStatusFailure);
            };
            
            // Enqueue the task
            [queue enqueueTask:[KTBTask taskWithName:@"EventualAbandonedTask"
                                            userInfo:nil
                                       availableDate:nil
                                          maxRetries:3
                                          useBackoff:NO]];
            
            [[expectFutureValue(theValue(attemptsCount)) shouldEventuallyBeforeTimingOutAfter(5)] equal:theValue(4)];
        });
        
        it(@"never abandons tasks with maxRetries set to KTBTaskAlwaysRetry", ^{
            queue.executionBlock = ^(KTBTask *task, KTBTaskCompletionBlock completion) {
                completion(KTBTaskStatusFailure);
            };
            
            // Enqueue the task
            [queue enqueueTask:[KTBTask taskWithName:@"NeverAbandonedTask"
                                            userInfo:nil
                                       availableDate:nil
                                          maxRetries:KTBTaskAlwaysRetry
                                          useBackoff:NO]];
            
            [[expectFutureValue(theValue([queue containsTaskWithName:@"NeverAbandonedTask"])) shouldEventuallyBeforeTimingOutAfter(5)] beYes];
        });
        
        it(@"doesn't attempt tasks when suspended", ^{
            __block NSUInteger attemptsCount = 0;
            queue.executionBlock = ^(KTBTask *task, KTBTaskCompletionBlock completion) {
                attemptsCount++;
                completion(KTBTaskStatusSuccess);
            };
            // Suspend the queue
            queue.suspended = YES;
            
            // Enqueue the task
            [queue enqueueTaskWithName:@"NeverAttemptedTask" userInfo:nil];
            
            [[expectFutureValue(theValue(attemptsCount)) shouldEventually] equal:theValue(0)];
        });
        
        it(@"can prohibit backoff", ^{
            __block NSUInteger attemptsCount = 0;
            __block NSDate *lastExecutionDate = nil;
            queue.executionBlock = ^(KTBTask *task, KTBTaskCompletionBlock completion) {
                attemptsCount++;
                lastExecutionDate = [NSDate date];
                if (attemptsCount < 3) {
                    completion(KTBTaskStatusFailure);
                }
                else {
                    completion(KTBTaskStatusSuccess);
                }
            };
            // Don't allow backoff
            queue.prohibitsBackoff = YES;
            
            // Enqueue the task
            [queue enqueueTaskWithName:@"NoBackoffTask" userInfo:nil];
            
            [[expectFutureValue(theValue(attemptsCount)) shouldEventually] equal:theValue(3)];
            [[expectFutureValue(theValue(-[lastExecutionDate timeIntervalSinceNow] < 1)) should] beYes];
        });
        
        it(@"allows customization of the backoff timer", ^{
            __block NSUInteger attemptsCount = 0;
            __block NSDate *lastExecutionDate = nil;
            NSDate *testStartDate = [NSDate date];
            queue.executionBlock = ^(KTBTask *task, KTBTaskCompletionBlock completion) {
                attemptsCount++;
                lastExecutionDate = [NSDate date];
                if (attemptsCount < 3) {
                    completion(KTBTaskStatusFailure);
                }
                else {
                    completion(KTBTaskStatusSuccess);
                }
            };
            
            queue.backoffPollingInterval = 3;
            
            // Enqueue the task
            [queue enqueueTaskWithName:@"FailingTask" userInfo:nil];
            
            [[expectFutureValue(theValue(queue.pollingTimer.timeInterval)) shouldEventually] equal:theValue(3)];
            [[expectFutureValue(theValue(attemptsCount)) shouldEventuallyBeforeTimingOutAfter(10)] equal:theValue(3)];
            [[expectFutureValue(theValue([lastExecutionDate timeIntervalSinceDate:testStartDate] > queue.backoffPollingInterval)) should] beYes];
        });
        
        it(@"doesn't attempt tasks after being deleted", ^{
            queue.executionBlock = ^(KTBTask *task, KTBTaskCompletionBlock completion) {
                completion(KTBTaskStatusSuccess);
            };
            
            // Delete queue
            [queue deleteQueue];
            
            // Enqueue the task
            [queue enqueueTaskWithName:@"NoBackoffTask" userInfo:nil];
            
            [[theValue([queue count]) should] beZero];
        });
    });
    
    context(@"with a basic delegate", ^{
        // TODO: replace with let when Kiwi's podspec is updated
        __block KTBTaskQueue *queue = nil;
        __block TaskQueueSpecDelegate *delegate = nil;
        beforeEach(^{
            queue = [KTBTaskQueue queueInMemory];
            delegate = [TaskQueueSpecDelegate new];
            queue.delegate = delegate;
        });
        afterEach(^{
            [queue deleteQueue];
            queue = nil;
        });
        
        it(@"provides the task and queue to the delegate", ^{
            // Enqueue a task
            [queue enqueueTaskWithName:@"ATask" userInfo:nil];
            
            [[expectFutureValue(delegate.lastTask.name) shouldEventually] equal:@"ATask"];
            [[expectFutureValue(delegate.lastQueue) shouldEventually] equal:queue];
        });
        
        it(@"allows task execution", ^{
            // Enqueue the task
            [queue enqueueTaskWithName:@"ATask" userInfo:nil];
            
            // Queue should contain it after being added
            [[theValue([queue containsTaskWithName:@"ATask"]) should] beYes];
            
            // Queue shouldn't contain it after execution
            [[expectFutureValue(delegate.lastTask.name) shouldEventually] equal:@"ATask"];
        });
        
        it(@"supplies userInfo data during execution", ^{
            // Enqueue the task
            NSDictionary *expectedUserInfo = @{
                                               @"MyData": @"IsImportant!",
                                               @"SoIsThis": @2
                                               };
            [queue enqueueTaskWithName:@"ATask" userInfo:expectedUserInfo];
            
            [[expectFutureValue(delegate.lastTask.userInfo) shouldEventually] equal:expectedUserInfo];
        });
        
        it(@"retries failed tasks", ^{
            delegate.calloutBlock = ^(KTBTaskQueue *innerQueue, KTBTask *task, KTBTaskCompletionBlock completion) {
                // Succeed on the fourth try
                if (task.retryCount < 3) {
                    completion(KTBTaskStatusFailure);
                }
                else {
                    completion(KTBTaskStatusSuccess);
                }
            };
            
            // Enqueue the task
            [queue enqueueTask:[KTBTask taskWithName:@"FailingTask"
                                            userInfo:nil
                                       availableDate:nil
                                          maxRetries:3
                                          useBackoff:NO]];
            
            [[expectFutureValue(theValue(delegate.lastTask.retryCount)) shouldEventually] equal:theValue(3)];
        });
        
        it(@"retries failed tasks with backoff", ^{
            __block NSDate *lastExecutionDate = nil;
            NSDate *testStartDate = [NSDate date];
            
            delegate.calloutBlock = ^(KTBTaskQueue *innerQueue, KTBTask *task, KTBTaskCompletionBlock completion) {
                lastExecutionDate = [NSDate date];
                // Succeed on the third try
                if (task.retryCount < 2) {
                    completion(KTBTaskStatusFailure);
                }
                else {
                    completion(KTBTaskStatusSuccess);
                }
            };
            
            // Enqueue the task
            [queue enqueueTaskWithName:@"FailingTask" userInfo:nil];
            
            [[expectFutureValue(theValue(delegate.lastTask.retryCount)) shouldEventuallyBeforeTimingOutAfter(60)] equal:theValue(2)];
            [[expectFutureValue(theValue([lastExecutionDate timeIntervalSinceDate:testStartDate] > queue.backoffPollingInterval)) shouldEventuallyBeforeTimingOutAfter(60)] beYes];
        });
        
        it(@"doesn't retry abandoned tasks", ^{
            delegate.calloutBlock = ^(KTBTaskQueue *innerQueue, KTBTask *task, KTBTaskCompletionBlock completion) {
                completion(KTBTaskStatusAbandon);
            };
            
            // Enqueue the task
            [queue enqueueTaskWithName:@"AbandonedTask" userInfo:nil];
            
            [[expectFutureValue(theValue([queue containsTaskWithName:@"AbandonedTask"])) shouldEventually] beNo];
        });
        
        it(@"abandons tasks after a number of retries", ^{
            __block NSUInteger attemptsCount = 0;            
            delegate.calloutBlock = ^(KTBTaskQueue *innerQueue, KTBTask *task, KTBTaskCompletionBlock completion) {
                attemptsCount++;
                completion(KTBTaskStatusFailure);
            };
            
            // Enqueue the task
            [queue enqueueTask:[KTBTask taskWithName:@"EventualAbandonedTask"
                                            userInfo:nil
                                       availableDate:nil
                                          maxRetries:3
                                          useBackoff:NO]];
            
            [[expectFutureValue(theValue(attemptsCount)) shouldEventuallyBeforeTimingOutAfter(5)] equal:theValue(4)];
        });
        
        it(@"never abandons tasks with maxRetries set to KTBTaskAlwaysRetry", ^{
            delegate.calloutBlock = ^(KTBTaskQueue *innerQueue, KTBTask *task, KTBTaskCompletionBlock completion) {
                completion(KTBTaskStatusFailure);
            };
            
            // Enqueue the task
            [queue enqueueTask:[KTBTask taskWithName:@"NeverAbandonedTask"
                                            userInfo:nil
                                       availableDate:nil
                                          maxRetries:KTBTaskAlwaysRetry
                                          useBackoff:NO]];
            
            [[expectFutureValue(theValue([queue containsTaskWithName:@"NeverAbandonedTask"])) shouldEventuallyBeforeTimingOutAfter(5)] beYes];
        });
        
        it(@"doesn't attempt tasks when suspended", ^{
            // Suspend the queue
            queue.suspended = YES;
            
            // Enqueue the task
            [queue enqueueTaskWithName:@"NeverAttemptedTask" userInfo:nil];
            
            [[expectFutureValue(delegate.lastTask) shouldEventually] beNil];
        });
        
        it(@"can prohibit backoff", ^{
            __block NSUInteger attemptsCount = 0;
            __block NSDate *lastExecutionDate = nil;
            delegate.calloutBlock = ^(KTBTaskQueue *innerQueue, KTBTask *task, KTBTaskCompletionBlock completion) {
                attemptsCount++;
                lastExecutionDate = [NSDate date];
                if (attemptsCount < 3) {
                    completion(KTBTaskStatusFailure);
                }
                else {
                    completion(KTBTaskStatusSuccess);
                }
            };
            
            // Don't allow backoff
            queue.prohibitsBackoff = YES;
            
            // Enqueue the task
            [queue enqueueTaskWithName:@"NoBackoffTask" userInfo:nil];
            
            [[expectFutureValue(theValue(attemptsCount)) shouldEventually] equal:theValue(3)];
            [[expectFutureValue(theValue(-[lastExecutionDate timeIntervalSinceNow] < 1)) should] beYes];
        });
        
        it(@"allows customization of the backoff timer", ^{
            __block NSUInteger attemptsCount = 0;
            __block NSDate *lastExecutionDate = nil;
            NSDate *testStartDate = [NSDate date];
            delegate.calloutBlock = ^(KTBTaskQueue *innerQueue, KTBTask *task, KTBTaskCompletionBlock completion) {
                attemptsCount++;
                lastExecutionDate = [NSDate date];
                if (attemptsCount < 3) {
                    completion(KTBTaskStatusFailure);
                }
                else {
                    completion(KTBTaskStatusSuccess);
                }
            };
            
            queue.backoffPollingInterval = 3;
            
            // Enqueue the task
            [queue enqueueTaskWithName:@"FailingTask" userInfo:nil];
            
            [[expectFutureValue(theValue(queue.pollingTimer.timeInterval)) shouldEventually] equal:theValue(3)];
            [[expectFutureValue(theValue(attemptsCount)) shouldEventuallyBeforeTimingOutAfter(10)] equal:theValue(3)];
            [[expectFutureValue(theValue([lastExecutionDate timeIntervalSinceDate:testStartDate] > queue.backoffPollingInterval)) should] beYes];
        });
        
        it(@"doesn't attempt tasks after being deleted", ^{
            // Delete queue
            [queue deleteQueue];
            
            // Enqueue the task
            [queue enqueueTaskWithName:@"NoBackoffTask" userInfo:nil];
            
            [[theValue([queue count]) should] beZero];
            [[delegate.lastTask should] beNil];
        });
    });
    
    context(@"with a complex delegate", ^{
        // TODO: replace with let when Kiwi's podspec is updated
        __block KTBTaskQueue *queue = nil;
        __block TaskQueueSpecFullDelegate *delegate = nil;
        beforeEach(^{
            queue = [KTBTaskQueue queueInMemory];
            delegate = [TaskQueueSpecFullDelegate new];
            queue.delegate = delegate;
        });
        afterEach(^{
            [queue deleteQueue];
            queue = nil;
        });
        
        it(@"reports abandoned tasks", ^{
            delegate.calloutBlock = ^(KTBTaskQueue *innerQueue, KTBTask *task, KTBTaskCompletionBlock completion) {
                completion(KTBTaskStatusAbandon);
            };
            
            // Enqueue the task
            [queue enqueueTaskWithName:@"AbandonedTask" userInfo:nil];
            
            [[expectFutureValue(delegate.lastAbandonedTask.name) shouldEventually] equal:@"AbandonedTask"];
        });
        
        it(@"can dynamically alter backoff times", ^{
            __block NSDate *lastExecutionDate = nil;
            NSDate *testStartDate = [NSDate date];
            
            delegate.calloutBlock = ^(KTBTaskQueue *innerQueue, KTBTask *task, KTBTaskCompletionBlock completion) {
                lastExecutionDate = [NSDate date];
                // Succeed on the third try
                if (task.retryCount < 2) {
                    completion(KTBTaskStatusFailure);
                }
                else {
                    completion(KTBTaskStatusSuccess);
                }
            };
            delegate.delayBlock = ^(KTBTask *taskToDelay, NSDate *suggestedDate) {
                return testStartDate;
            };
            
            // Enqueue the task
            [queue enqueueTaskWithName:@"FailingTask" userInfo:nil];
            
            [[expectFutureValue(theValue(delegate.lastTask.retryCount)) shouldEventually] equal:theValue(2)];
            [[expectFutureValue(theValue([lastExecutionDate timeIntervalSinceDate:testStartDate] < 1)) shouldEventually] beYes];
        });
    });
});

SPEC_END
