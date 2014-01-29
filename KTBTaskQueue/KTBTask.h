//
//  KTBTask.h
//  KTBTask
//
//  Created by Kevin Barrett on 1/23/14.
//  Copyright (c) 2014 Little Spindle, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>

extern const NSInteger KTBTaskMaxRetriesDefault;
extern const NSInteger KTBTaskAlwaysRetry;

@class FMResultSet;

/**
 A @c KTBTask is an immutable representation of a task queued in a @c KTBTaskQueue.
 As it is immutable, changing the task returned by a delegate method or block from @c KTBTaskQueue
 will not alter the task's behavior.
 */
@interface KTBTask : NSObject
/**
 A unique number identifier for the task. Only non-nil once the task has been enqueued.
 */
@property (readonly, nonatomic, strong) NSNumber *taskID;
/**
 The task's name. Does not need to be unique.
 
 Can be used to categoryize tasks, identify individual tasks, or pretty much anything else a string can do.
 */
@property (readonly, nonatomic, copy) NSString *name;
/**
 A dictionary used to attach arbitrary data to the task. Defaults to an empty dictionary.
 
 @note Keys must be strings and values much be JSON-serializable.
 */
@property (readonly, nonatomic, strong) NSDictionary *userInfo;
/**
 Date this task was created.
 */
@property (readonly, nonatomic, strong) NSDate *createdDate;
/**
 Date after which this task is available for dequeuing and executing. Defaults to now.
 */
@property (readonly, nonatomic, strong) NSDate *availableDate;
/**
 The number of times this task has been retried.
 @note This is equivalent to the number of times this task has been attempted + 1 for the first (untried) attempt.
 */
@property (readonly, nonatomic, assign) NSInteger retryCount;
/**
 The maximum number of times this task will be retried. Defaults to 10.
 Setting this to @c KTBTaskAlwaysRetry will prevent the task from ever being abandoned due to high retry count. The task will be tried until it succeeds.
 @note The first attempt does not count as a retry, so a task will be tried a total of @c maxRetries+1 times.
 */
@property (readonly, nonatomic, assign) NSInteger maxRetries;
/**
 Whether to retry a task immediately or wait for some time before retrying. Defaults to @c YES. The default can be changed with the setRetryWithBackoffDefault: class method.
 @note When @c YES, the amount of time waited between retries increases with each retry.
 */
@property (readonly, nonatomic, assign) BOOL retryWithBackoff;

/**
 Simple constructor to return a task. The task will be available immediately, will abandon after 10 retries, and will use backoff.
 @param name The name of the task.
 @param userInfo Arbitrary JSON-encodable data for this task.
 */
+ (instancetype)taskWithName:(NSString *)name userInfo:(NSDictionary *)userInfo;
/**
 Full constructor. Passing in @c nil for @c userInfo and @c availableDate will treat them as the default: an empty dictionary and now, respectively.
 @param name The name of the task.
 @param userInfo Arbitrary JSON-encodable data for this task.
 @param availableDate Date this task should be available for execution. Passing @c nil will make the task available immediately.
 @param maxRetries Number of times to retry this task. Passing in @c KTBTaskAlwaysRetry will prevent this task from abandoning due to high retry count.
 @param useBackoff Whether to retry the task with exponential backoff delay or immediately.
 */
+ (instancetype)taskWithName:(NSString *)name userInfo:(NSDictionary *)userInfo availableDate:(NSDate *)availableDate maxRetries:(NSUInteger)maxRetries useBackoff:(BOOL)useBackoff;
/**
 Changes the default value of @c retryWithBackoff on newly-created tasks. The default is @c YES.
 */
+ (void)setRetryWithBackoffDefault:(BOOL)defaultRetryWithBackoffValue;
/**
 @return @c YES if the task can be retried.
 */
- (BOOL)canBeRetried;

// Ignore me!
+ (instancetype)taskWithResultSet:(FMResultSet *)resultSet;
@end
