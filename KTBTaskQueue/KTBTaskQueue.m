//
//  KTBTaskQueue.m
//  KTBTaskQueue
//
//  Created by Kevin Barrett on 1/23/14.
//  Copyright (c) 2014 Little Spindle, LLC. All rights reserved.
//

#import "KTBTaskQueue.h"
#import "KTBTask.h"
#import <FMDB/FMDatabaseQueue.h>
#import <FMDB/FMDatabase.h>

void KTBDispatchSyncOnMainQueue(void (^block)(void)) {
    if ([NSThread isMainThread]) {
        block();
    }
    else {
        dispatch_sync(dispatch_get_main_queue(), block);
    }
}

void KTBDispatchAsyncOnMainQueue(void (^block)(void)) {
    if ([NSThread isMainThread]) {
        block();
    }
    else {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

static dispatch_queue_t task_queue_processing_queue() {
    static dispatch_queue_t ktb_task_queue_processing_queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ktb_task_queue_processing_queue = dispatch_queue_create("com.littlespindle.taskqueue.processing", DISPATCH_QUEUE_SERIAL);
    });
    
    return ktb_task_queue_processing_queue;
}

const NSTimeInterval KTBTaskQueueDefaultPollingInterval = 10;

@interface KTBTask (QueueAdditions)
- (NSString *)userInfoString;
- (NSNumber *)createdDateNumber;
- (NSNumber *)availableDateNumber;
- (NSDate *)nextAvailableDateWithBackoffInterval:(NSTimeInterval)backoffInterval;
@end

@interface KTBTaskQueue ()
@property (readwrite, nonatomic, strong) FMDatabaseQueue *databaseQueue;
@property (readwrite, nonatomic, copy) NSString *pathToDatabase;
@property (readwrite, nonatomic, strong) NSTimer *pollingTimer;
@property (readwrite, atomic, assign, getter = isProcessing) BOOL processing;
/**
 A valid queue has not been deleted with @c deleteQueue.
 Once a queue is deleted it is considered invalid and will no longer accept tasks.
 */
@property (readwrite, nonatomic, assign) BOOL valid;
@end

@implementation KTBTaskQueue

+ (instancetype)queueAtPath:(NSString *)filePath {
    return [self queueAtPath:filePath delegate:nil];
}

+ (instancetype)queueAtPath:(NSString *)filePath delegate:(id<KTBTaskQueueDelegate>)delegate {
    return [[self alloc] initWithPath:filePath delegate:delegate];
}

+ (instancetype)queueInMemory {
    return [self queueInMemoryWithDelegate:nil];
}

+ (instancetype)queueInMemoryWithDelegate:(id<KTBTaskQueueDelegate>)delegate {
    return [[self alloc] initWithPath:nil delegate:delegate];
}

- (instancetype)initWithPath:(NSString *)filePath delegate:(id<KTBTaskQueueDelegate>)delegate {
    self = [super init];
    if (self) {
        if (filePath) {
            NSURL *pathURL = [NSURL fileURLWithPath:filePath];
            if (![[pathURL pathExtension] length]) {
                filePath = [filePath stringByAppendingString:@".db"];
            }
        }
        
        [self setupDatabaseQueueAtPath:filePath];
        
        self.delegate = delegate;
        
        _suspended = NO;
        self.processing = NO;
        _prohibitsBackoff = NO;
        self.valid = YES;
        
        _backoffPollingInterval = KTBTaskQueueDefaultPollingInterval;
        [self startPollingTimer];
    }
    return self;
}

- (instancetype)init {
    return [self initWithPath:nil delegate:nil];
}

- (void)dealloc {
    _valid = NO;
    
    // Stop timer and close database
    [self stopPollingTimer];
    [self.databaseQueue close];
    _databaseQueue = nil;
}

#pragma mark - Control

- (void)setSuspended:(BOOL)suspended {
    _suspended = suspended;
    
    if (suspended) {
        [self stopPollingTimer];
    }
    else {
        [self dequeueNextTask];
    }
}

- (void)setProhibitsBackoff:(BOOL)prohibitsBackoff {
    _prohibitsBackoff = prohibitsBackoff;
    
    if (prohibitsBackoff) {
        if (self.pollingTimer) {
            [self stopPollingTimer];
        }
    }
    else if (self.valid) {
        [self dequeueNextTask];
    }
}

- (void)setBackoffPollingInterval:(NSTimeInterval)backoffPollingInterval {
    _backoffPollingInterval = backoffPollingInterval;
    
    // Reset polling timer
    if (self.pollingTimer) {
        [self stopPollingTimer];
        [self dequeueNextTask];
    }
}

#pragma mark - Adding Tasks

- (void)enqueueTaskWithName:(NSString *)name userInfo:(NSDictionary *)userInfo {
    [self enqueueTask:[KTBTask taskWithName:name userInfo:userInfo]];
}

- (void)enqueueTask:(KTBTask *)task {
    if (self.valid) {
        [self insertTask:task];
        [self dequeueNextTask];
    }
}

#pragma mark - Running Tasks and Timing

- (void)startPollingTimer {
    KTBDispatchSyncOnMainQueue(^{
        if (!self.pollingTimer && !self.suspended) {
            // The polling timer repeats until one or more tasks are available for dequeueing.
            // The tasks are dequeued serially. Once all available tasks have been dequeued, the timer is resumed.
            self.pollingTimer = [NSTimer scheduledTimerWithTimeInterval:self.backoffPollingInterval target:self selector:@selector(pollingTimerDidFire:) userInfo:nil repeats:YES];
            if ([self.pollingTimer respondsToSelector:@selector(setTolerance:)]) {
                // We can add a lot of tolerance because it's not terribly important when the timer fires.
                [self.pollingTimer setTolerance:self.backoffPollingInterval / 2];
            }
        }
    });
}

- (void)stopPollingTimer {
    KTBDispatchSyncOnMainQueue(^{
        [self.pollingTimer invalidate];
        self.pollingTimer = nil;
    });
    
}

- (void)pollingTimerDidFire:(NSTimer *)timer {
    [self dequeueNextTask];
}

- (void)dequeueNextTask {
    dispatch_async(task_queue_processing_queue(), ^{
        if (self.valid && !self.suspended && !self.processing && [self hasEligibleTasks]) {
            self.processing = YES;
            KTBTask *task = [self nextTask];
            if (task) {
                // Stop the timer
                [self stopPollingTimer];
                
                // Set completion block for responding to task results
                KTBTaskCompletionBlock completionBlock = ^(KTBTaskStatus result) {
                    // Respond to whatever the was to passed us
                    [self respondToResult:result forTask:task];
                    
                    // We're no longer processing.
                    // Either there are more tasks and we should move to the next one,
                    // or we should go back to polling intermittently.
                    self.processing = NO;
                    if ([self hasEligibleTasks]) {
                        KTBDispatchAsyncOnMainQueue(^{
                            [self dequeueNextTask];
                        });
                    }
                    else {
                        [self startPollingTimer];
                    }
                };
                
                if (self.executionBlock) {
                    // Use our assigned execution block to process the task
                    self.executionBlock(task, completionBlock);
                }
                else if (self.delegate) {
                    // Ask the delegate to process the task
                    [self.delegate taskQueue:self executeTask:task completion:completionBlock];
                }
                else {
                    completionBlock(KTBTaskStatusFailure);
                }
            }
            else {
                // There are no available tasks. Go back to polling.
                self.processing = NO;
                [self startPollingTimer];
            }
        }
    });
}

- (void)respondToResult:(KTBTaskStatus)result forTask:(KTBTask *)task {
    if (result == KTBTaskStatusSuccess) {
        // Remove the job from the queue
        [self deleteTask:task];
    }
    else if (result == KTBTaskStatusFailure) {
        if ([task canBeRetried]) {
            [self setRetryDataForTask:task];
        }
        else {
            [self abandonTask:task];
        }
    }
    else if (result == KTBTaskStatusAbandon) {
        [self abandonTask:task];
    }
}

- (void)abandonTask:(KTBTask *)task {
    if ([self.delegate respondsToSelector:@selector(taskQueue:willAbandonTask:)]) {
        [self.delegate taskQueue:self willAbandonTask:task];
    }
    [self deleteTask:task];
}

#pragma mark - Querying the Queue

- (NSUInteger)count {
    return [self numberOfTasks];
}

- (BOOL)containsTaskWithName:(NSString *)name {
    return [self taskWithName:name] != nil;
}

- (BOOL)containsTask:(KTBTask *)task {
    return [self taskWithID:task.taskID] != nil;
}

#pragma mark - Cleanup

// This is typically only used for testing
- (void)deleteQueue {
    // Queue is no longer valid, stop accepting and processing tasks
    self.valid = NO;
    self.processing = NO;

    // Stop timer and close database
    [self stopPollingTimer];
    [self.databaseQueue close];
    self.databaseQueue = nil;
    
    // Remove database from disk
    NSFileManager *manager = [NSFileManager new];
    [manager removeItemAtPath:self.pathToDatabase error:NULL];
    self.pathToDatabase = nil;
}

#pragma mark - Database Operations

- (void)setupDatabaseQueueAtPath:(NSString *)filePath {
    self.pathToDatabase = filePath;
    self.databaseQueue = [FMDatabaseQueue databaseQueueWithPath:filePath];
    // Create table
    [self.databaseQueue inDatabase:^(FMDatabase *db) {
        [db executeUpdate:
         @"CREATE TABLE IF NOT EXISTS tasks ("
         @"    id               INTEGER PRIMARY KEY AUTOINCREMENT,"
         @"    name             TEXT NOT NULL DEFAULT '',"
         @"    userInfo         TEXT NOT NULL DEFAULT '{}',"
         @"    createdDate      INTEGER NOT NULL,"
         @"    availableDate    INTEGER NOT NULL,"
         @"    retryCount       INTEGER NOT NULL DEFAULT 0,"
         @"    maxRetries       INTEGER NOT NULL DEFAULT 10,"
         @"    retryWithBackoff INTEGER NOT NULL DEFAULT 1"
         @");"
         ];
        [self checkErrorForDatabase:db stepDescription:[NSString stringWithFormat:@"initializing task queue at %@", filePath]];
    }];
}

- (void)insertTask:(KTBTask *)task {
    [self.databaseQueue inDatabase:^(FMDatabase *db) {
        [db executeUpdate:
         @"INSERT INTO tasks (name, userInfo, createdDate, availableDate, maxRetries, retryWithBackoff)"
         @"VALUES (?, ?, ?, ?, ?, ?)",
         task.name, [task userInfoString], [task createdDateNumber], [task availableDateNumber], @(task.maxRetries), @(!self.prohibitsBackoff && task.retryWithBackoff)];
        [self checkErrorForDatabase:db stepDescription:@"inserting task into task queue"];
    }];
}

- (BOOL)hasEligibleTasks {
    __block BOOL hasTasks = NO;
    
    [self.databaseQueue inDatabase:^(FMDatabase *db) {
        NSNumber *availableNowDateNumber = @([[NSDate date] timeIntervalSince1970]);
        FMResultSet *resultSet = [db executeQuery:@"SELECT count(id) AS count FROM tasks WHERE availableDate <= ?", availableNowDateNumber];
        [self checkErrorForDatabase:db stepDescription:@"checking for eligible tasks"];
        
        if ([resultSet next]) {
            hasTasks = ([resultSet intForColumn:@"count"] > 0);
        }
        
        [resultSet close];
    }];
    
    return hasTasks;
}

- (KTBTask *)nextTask {
    __block KTBTask *task = nil;
    [self.databaseQueue inDatabase:^(FMDatabase *db) {
        NSNumber *availableNowDateNumber = @([[NSDate date] timeIntervalSince1970]);
        FMResultSet *resultSet = [db executeQuery:@"SELECT * FROM tasks WHERE availableDate <= ? ORDER BY availableDate ASC LIMIT 1", availableNowDateNumber];
        [self checkErrorForDatabase:db stepDescription:@"selecting next eligible task"];
        
        if ([resultSet next]) {
            task = [KTBTask taskWithResultSet:resultSet];
        }
        
        [resultSet close];
    }];
    
    return task;
}

- (void)deleteTask:(KTBTask *)task {
    [self.databaseQueue inDatabase:^(FMDatabase *db) {
        [db executeUpdate:@"DELETE FROM tasks WHERE id = ?", task.taskID];
        [self checkErrorForDatabase:db stepDescription:@"deleting task from task queue"];
    }];
}

- (void)setRetryDataForTask:(KTBTask *)task {
    NSDate *nextAvailableDate = [task nextAvailableDateWithBackoffInterval:self.backoffPollingInterval];
    if ([self.delegate respondsToSelector:@selector(taskQueue:willDelayRetryOfTask:untilDate:)]) {
        nextAvailableDate = [self.delegate taskQueue:self willDelayRetryOfTask:task untilDate:nextAvailableDate];
    }
    
    [self.databaseQueue inDatabase:^(FMDatabase *db) {
        NSNumber *nextAvailableDateNumber = @([nextAvailableDate timeIntervalSince1970]);
        [db executeUpdate:@"UPDATE tasks SET retryCount = retryCount + 1, availableDate = ? WHERE id = ?", nextAvailableDateNumber, task.taskID];
        [self checkErrorForDatabase:db stepDescription:@"setting retry data for task"];
    }];
}

- (NSUInteger)numberOfTasks {
    __block NSUInteger count = 0;
    
    [self.databaseQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *resultSet = [db executeQuery:@"SELECT count(id) AS count FROM tasks"];
        [self checkErrorForDatabase:db stepDescription:@"getting number of tasks"];
        
        if ([resultSet next]) {
            count = (NSUInteger)[resultSet intForColumn:@"count"];
        }
        
        [resultSet close];
    }];
    
    return count;
}

- (KTBTask *)taskWithName:(NSString *)name {
    __block KTBTask *task = nil;
    [self.databaseQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *resultSet = [db executeQuery:@"SELECT * FROM tasks WHERE name = ? LIMIT 1", name];
        [self checkErrorForDatabase:db stepDescription:@"searching for a task by name"];
        
        if ([resultSet next]) {
            task = [KTBTask taskWithResultSet:resultSet];
        }
        
        [resultSet close];
    }];
    
    return task;
}

- (KTBTask *)taskWithID:(NSNumber *)taskID {
    __block KTBTask *task = nil;
    [self.databaseQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *resultSet = [db executeQuery:@"SELECT * FROM tasks WHERE id = ? LIMIT 1", taskID];
        [self checkErrorForDatabase:db stepDescription:@"searching for a task by ID"];
        
        if ([resultSet next]) {
            task = [KTBTask taskWithResultSet:resultSet];
        }
        
        [resultSet close];
    }];
    
    return task;
}

- (BOOL)checkErrorForDatabase:(FMDatabase *)db stepDescription:(NSString *)description {
    BOOL hadError = [db hadError];
    
    if (hadError) {
        if (!description) {
            description = @"doing something";
        }
        
        NSLog(@"Error %@: %@", description, [db lastError]);
    }
    
    return hadError;
}

- (NSString *)description {
    NSMutableString *description = [NSMutableString new];
    [description appendFormat:@"KTBTaskQueue (%d tasks):\n", [self numberOfTasks]];
    [self.databaseQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *resultSet = [db executeQuery:@"SELECT * FROM tasks ORDER BY availableDate ASC"];
        [self checkErrorForDatabase:db stepDescription:@"dumping task list"];
        
        while ([resultSet next]) {
            KTBTask *task = [KTBTask taskWithResultSet:resultSet];
            [description appendString:[task description]];
            [description appendString:@"\n"];
        }
        
        [resultSet close];
    }];
    
    return description;
}

@end

#pragma mark - KTBTask (QueueAdditions)

@implementation KTBTask (QueueAdditions)

- (NSString *)userInfoString {
    return [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:self.userInfo options:0 error:NULL] encoding:NSUTF8StringEncoding];
}

- (NSNumber *)createdDateNumber {
    return @([self.createdDate timeIntervalSince1970]);
}

- (NSNumber *)availableDateNumber {
    return @([self.availableDate timeIntervalSince1970]);
}

- (NSDate *)nextAvailableDateWithBackoffInterval:(NSTimeInterval)backoffInterval {
    if (self.retryWithBackoff) {
        // 10 * 2^retryCount - 1
        // Subtract 1 so it catches next poll
        return [NSDate dateWithTimeIntervalSinceNow:(backoffInterval * pow(2, self.retryCount)) - 1];
    }
    else {
        return self.createdDate;
    }
}

@end
