//
//  TaskQueueSpecDelegate.m
//  KTBTaskQueue
//
//  Created by Kevin Barrett on 1/25/14.
//  Copyright (c) 2014 Little Spindle, LLC. All rights reserved.
//

#import "TaskQueueSpecDelegate.h"

@interface TaskQueueSpecDelegate ()
@property (readwrite, nonatomic, strong) KTBTaskQueue *lastQueue;
@property (readwrite, nonatomic, strong) KTBTask *lastTask;
@end

@implementation TaskQueueSpecDelegate

- (void)taskQueue:(KTBTaskQueue *)queue executeTask:(KTBTask *)task completion:(KTBTaskCompletionBlock)completion {
    self.lastQueue = queue;
    self.lastTask = task;
    
    if (self.calloutBlock) {
        self.calloutBlock(queue, task, completion);
    }
    else {
        completion(KTBTaskStatusSuccess);
    }
}

@end
