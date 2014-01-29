//
//  KTBTaskQueueDelegate.h
//  KTBTaskQueueDelegate
//
//  Created by Kevin Barrett on 1/24/14.
//  Copyright (c) 2014 Little Spindle, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, KTBTaskStatus) {
    KTBTaskStatusSuccess,
    KTBTaskStatusFailure,
    KTBTaskStatusAbandon
};

typedef void(^KTBTaskCompletionBlock)(KTBTaskStatus result);

@class KTBTaskQueue;
@class KTBTask;

/**
 The delegate protocol for a KTBTaskQueue. Delegates must implement @c taskQueue:executeTask:completion: so that tasks are executed; other methods are optional.
 */
@protocol KTBTaskQueueDelegate <NSObject>
/**
 Called by the task queue on its delegate to execute a task. Whether the task completes successfully,
 fails and you want to retry, or fails and you want to give up, you must call the completion block
 with a @c KTBTaskStatus flag indicating the result.
 @param queue The queue making this delegate call.
 @param task A task model that encapsulates data about the thing to be executed.
 @param completion The completion block you must call when the task is finished or has failed.
 */
- (void)taskQueue:(KTBTaskQueue *)queue executeTask:(KTBTask *)task completion:(KTBTaskCompletionBlock)completion;
@optional
/**
 Used to inform the delegate when a task has been abandoned.
 @param queue The queue making this delegate call.
 @param task A task model that encapsulates data about the thing to be abandoned.
 */
- (void)taskQueue:(KTBTaskQueue *)queue willAbandonTask:(KTBTask *)task;
/**
 Called by the task queue when a task will be retried in the future. The task will be scheduled
 to be available after the date returned by this method. The @c date argument is the default available date,
 as determined by the queue.
 @param queue The queue making this delegate call.
 @param task A task model that encapsulates data about the thing to be retried later.
 @param date The date the queue has calculated as when to make the task next available.
 @note This method is only called when @c retryWithBackoff is set to @c YES on the task. Otherwise, the task is retried immediately.
 */
- (NSDate *)taskQueue:(KTBTaskQueue *)queue willDelayRetryOfTask:(KTBTask *)task untilDate:(NSDate *)date;
@end
