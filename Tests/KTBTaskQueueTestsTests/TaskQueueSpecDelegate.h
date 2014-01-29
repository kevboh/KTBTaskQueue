//
//  TaskQueueSpecDelegate.h
//  KTBTaskQueue
//
//  Created by Kevin Barrett on 1/25/14.
//  Copyright (c) 2014 Little Spindle, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <KTBTaskQueue/KTBTaskQueue.h>

typedef void(^TaskQueueSpecDelegateCalloutBlock)(KTBTaskQueue *queue, KTBTask *task, KTBTaskCompletionBlock completion);

@interface TaskQueueSpecDelegate : NSObject <KTBTaskQueueDelegate>
@property (readwrite, nonatomic, copy) TaskQueueSpecDelegateCalloutBlock calloutBlock;
@property (readonly, nonatomic, strong) KTBTaskQueue *lastQueue;
@property (readonly, nonatomic, strong) KTBTask *lastTask;
@end
