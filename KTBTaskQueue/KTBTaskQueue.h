//
//  KTBTaskQueue.h
//  KTBTaskQueue
//
//  Created by Kevin Barrett on 1/23/14.
//  Copyright (c) 2014 Little Spindle, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "KTBTaskQueueDelegate.h"
#import "KTBTask.h"

typedef void(^KTBTaskQueueExecutionBlock)(KTBTask *task, KTBTaskCompletionBlock completion);

@interface KTBTaskQueue : NSObject
@property (readwrite, nonatomic, weak) id<KTBTaskQueueDelegate> delegate;
/**
 @c YES if the queue is not actively dequeuing jobs, and @c NO if it is.

 Defaults to @c NO. Setting to @c YES will suspended the queue and prevent tasks from running
 until @c suspended is set to NO again.
 
 @note @c KTBTaskQueue is initialized in a non-suspended state, so the first enqueued
 task will automatically be run. Adding a task to a suspended queue does not un-suspend it.
 Setting @c suspended to @c NO will cause any tasks added in the interim to be run.
 */
@property (readwrite, nonatomic, assign, getter = isSuspended) BOOL suspended;
/**
 This is set to @c YES when the queue is actually processing a task, a serial action. @c NO when the queue is idle.
 */
@property (readonly, atomic, assign, getter = isProcessing) BOOL processing;
/**
 If set, this block will be used instead of the @c taskQueue:executeTask:completion:
 delegate method to execute tasks.
 @note The other (optional) delegate methods will still be called, if implemented.
 */
@property (readwrite, nonatomic, copy) KTBTaskQueueExecutionBlock executionBlock;
/**
 Setting @c prohibitsBackoff to @c YES will force tasks added to the queue to retry
 immediately without respect to the individual task's @c retryWithBackoff property.
 */
@property (readwrite, nonatomic, assign) BOOL prohibitsBackoff;
/**
 The time interval in seconds used to determine backoff retry times and how often the queue
 should check for available tasks. Defaults to 10 seconds.
 @note On iOS 7+ the queue will use the @c setTolerance: method on @c NSTimer to allow the
 polling timer to be coalesced with other timers by the system (and thus save energy),
 and as such this time interval may not be strictly adhered to.
 */
@property (readwrite, nonatomic, assign) NSTimeInterval backoffPollingInterval;

/**
 A constuctor that returns a queue persisted at @c filePath. The queue will save tasks to disk
 at that location. As such, tasks will persist and be retried across app launches as long as 
 @c filePath remains the same.
 @param filePath The location on disk to store the queue.
 @return A new disk-based queue.
 */
+ (instancetype)queueAtPath:(NSString *)filePath;
/**
 A constuctor that returns a queue persisted at @c filePath and sets the delegate.
 @c filePath remains the same.
 @param filePath The location on disk to store the queue.
 @param delegate Delegate to use for task execution.
 @return A new disk-based queue.
 */
+ (instancetype)queueAtPath:(NSString *)filePath delegate:(id<KTBTaskQueueDelegate>)delegate;
/**
 A constructor that returns a queue that exists only in memory. Useful for one-off task tracking
 or testing.
 @return A new memory-based queue.
 */
+ (instancetype)queueInMemory;
/**
 A constructor that returns a queue that exists only in memory and sets the delegate.
 @param delegate Delegate to use for task execution.
 @return A new memory-based queue.
 */
+ (instancetype)queueInMemoryWithDelegate:(id<KTBTaskQueueDelegate>)delegate;
/**
 Designated initializer.
 @param filePath A path on disk to store the queue, or @c nil if the queue should only exist in memory.
 @param delegate Delegate to use for task execution.
 @return A new queue.
 */
- (instancetype)initWithPath:(NSString *)filePath delegate:(id<KTBTaskQueueDelegate>)delegate;

/**
 A shorthand way of enqueuing tasks when all you need is a name and a dictionary. Task will (almost)
 immediately be attempted via delegate or execution block.
 @param name The name of the task to enqueue.
 @param userInfo An optional dictionary of data to store in the task. Must be JSON-serializable.
 */
- (void)enqueueTaskWithName:(NSString *)name userInfo:(NSDictionary *)userInfo;
/**
 Enqueue a task. See @c KTBTask.h for how to create tasks. Task will (almost)
 immediately be attempted via delegate or execution block.
 @param task The task to enqueue.
 */
- (void)enqueueTask:(KTBTask *)task;

/**
 The number of tasks in the queue.
 */
- (NSUInteger)count;
/**
 Whether the queue contains a task with the given name.
 @param name Name of task to look for in the queue.
 */
- (BOOL)containsTaskWithName:(NSString *)name;
/**
 Whether the queue contains this exact task.
 Task must have already been enqueued and should be an argument passed to the delegate or execution block, not a new task.
 @param task Task to look for. Must be a product of the queue, not a newly created task.
 */
- (BOOL)containsTask:(KTBTask *)task;

/**
 Deletes the queue from disk or memory and renders it invalid.
 @note Tasks enqueued after the queue has been deleted are never attempted. Tasks in the queue when it is deleted are lost.
 */
- (void)deleteQueue;

@end
