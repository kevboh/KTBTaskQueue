//
//  TaskSpec.m
//  KTBTaskQueue
//
//  Created by Kevin Barrett on 1/25/14.
//  Copyright (c) 2014 Little Spindle, LLC. All rights reserved.
//

#import <Kiwi/Kiwi.h>
#import <KTBTaskQueue/KTBTask.h>

@interface KTBTask (TestAdditions)
- (void)setRetryCount:(NSUInteger)retryCount;
@end

SPEC_BEGIN(TaskSpec)

describe(@"KTBTask", ^{
    it(@"cannot be retried more than maxRetries times", ^{
        KTBTask *task = [KTBTask taskWithName:@"ATask"
                                     userInfo:nil
                                availableDate:nil
                                   maxRetries:1
                                   useBackoff:YES];
        [[theValue([task canBeRetried]) should] beYes];
        
        [task setRetryCount:1];
        [[theValue([task canBeRetried]) should] beNo];
    });
    
    it(@"has a default and allows custom available dates", ^{
        KTBTask *task = [KTBTask taskWithName:@"ATask"
                                     userInfo:nil
                                availableDate:nil
                                   maxRetries:1
                                   useBackoff:YES];
        [[theValue(-[task.availableDate timeIntervalSinceNow]) should] beLessThan:theValue(1)];
        
        NSDate *customDate = [NSDate dateWithTimeIntervalSinceReferenceDate:0];
        KTBTask *datedTask = [KTBTask taskWithName:@"DatedTask"
                                          userInfo:nil
                                     availableDate:customDate
                                        maxRetries:1
                                        useBackoff:YES];
        [[datedTask.availableDate should] equal:customDate];
    });
    
    it(@"allows task-wide turning off of retry backoff", ^{
        [KTBTask setRetryWithBackoffDefault:NO];
        KTBTask *defaultTaskNo = [KTBTask taskWithName:@"DefaultTask" userInfo:nil];
        [[theValue(defaultTaskNo.retryWithBackoff) should] beNo];
        
        [KTBTask setRetryWithBackoffDefault:YES];
        KTBTask *defaultTaskYes = [KTBTask taskWithName:@"DefaultTask" userInfo:nil];
        [[theValue(defaultTaskYes.retryWithBackoff) should] beYes];

    });
});

SPEC_END
