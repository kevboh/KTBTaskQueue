//
//  TaskQueueSpecFullDelegate.m
//  KTBTaskQueue
//
//  Created by Kevin Barrett on 1/28/14.
//  Copyright (c) 2014 Little Spindle, LLC. All rights reserved.
//

#import "TaskQueueSpecFullDelegate.h"

@interface TaskQueueSpecFullDelegate ()
@property (readwrite, nonatomic, strong) KTBTask *lastAbandonedTask;
@end

@implementation TaskQueueSpecFullDelegate

- (void)taskQueue:(KTBTaskQueue *)queue willAbandonTask:(KTBTask *)task {
    self.lastAbandonedTask = task;
}

- (NSDate *)taskQueue:(KTBTaskQueue *)queue willDelayRetryOfTask:(KTBTask *)task untilDate:(NSDate *)date {
    if (self.delayBlock) {
        return self.delayBlock(task, date);
    }
    return date;
}

@end
