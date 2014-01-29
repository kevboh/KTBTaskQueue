//
//  TaskQueueSpecFullDelegate.h
//  KTBTaskQueue
//
//  Created by Kevin Barrett on 1/28/14.
//  Copyright (c) 2014 Little Spindle, LLC. All rights reserved.
//

#import "TaskQueueSpecDelegate.h"

typedef NSDate *(^TaskQueueSpecFullDelegateDelayBlock)(KTBTask *taskToDelay, NSDate *suggestedDate);

@interface TaskQueueSpecFullDelegate : TaskQueueSpecDelegate
@property (readonly, nonatomic, strong) KTBTask *lastAbandonedTask;
@property (readwrite, nonatomic, copy) TaskQueueSpecFullDelegateDelayBlock delayBlock;
@end
