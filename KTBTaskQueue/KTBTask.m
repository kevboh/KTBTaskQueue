//
//  KTBTask.m
//  KTBTask
//
//  Created by Kevin Barrett on 1/23/14.
//  Copyright (c) 2014 Little Spindle, LLC. All rights reserved.
//

#import "KTBTask.h"
#import <FMDB/FMResultSet.h>

const NSInteger KTBTaskMaxRetriesDefault = 10;
const NSInteger KTBTaskAlwaysRetry = -1;
static BOOL KTBTaskRetryWithBackoffDefault = YES;

@interface KTBTask ()
@property (readwrite, nonatomic, strong) NSNumber *taskID;
@property (readwrite, nonatomic, copy) NSString *name;
@property (readwrite, nonatomic, strong) NSDictionary *userInfo;
@property (readwrite, nonatomic, strong) NSDate *createdDate;
@property (readwrite, nonatomic, strong) NSDate *availableDate;
@property (readwrite, nonatomic, assign) NSInteger retryCount;
@property (readwrite, nonatomic, assign) NSInteger maxRetries;
@property (readwrite, nonatomic, assign) BOOL retryWithBackoff;
@end

@implementation KTBTask

+ (instancetype)taskWithName:(NSString *)name userInfo:(NSDictionary *)userInfo {
    return [self taskWithName:name userInfo:userInfo availableDate:[NSDate date] maxRetries:KTBTaskMaxRetriesDefault useBackoff:KTBTaskRetryWithBackoffDefault];
}

+ (instancetype)taskWithName:(NSString *)name userInfo:(NSDictionary *)userInfo availableDate:(NSDate *)availableDate maxRetries:(NSInteger)maxRetries useBackoff:(BOOL)useBackoff {
    KTBTask *task = [KTBTask new];
    task.name = name;
    task.userInfo = userInfo ?: @{};
    task.availableDate = availableDate ?: [NSDate date];
    task.maxRetries = maxRetries;
    task.retryWithBackoff = useBackoff;
    return task;
}

+ (instancetype)taskWithResultSet:(FMResultSet *)resultSet {
    NSDictionary *resultDictionary = [resultSet resultDictionary];
    
    KTBTask *task = [KTBTask new];
    task.taskID = resultDictionary[@"id"];
    task.name = resultDictionary[@"name"];
    task.userInfo = [NSJSONSerialization JSONObjectWithData:[resultDictionary[@"userInfo"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL] ?: @{};
    task.createdDate = [NSDate dateWithTimeIntervalSince1970:[resultDictionary[@"createdDate"] integerValue]];
    task.availableDate = [NSDate dateWithTimeIntervalSince1970:[resultDictionary[@"availableDate"] integerValue]];
    task.retryCount = [resultDictionary[@"retryCount"] integerValue];
    task.maxRetries = [resultDictionary[@"maxRetries"] integerValue];
    task.retryWithBackoff = [resultDictionary[@"retryWithBackoff"] boolValue];
    return task;
}

+ (void)setRetryWithBackoffDefault:(BOOL)defaultRetryWithBackoffValue {
    KTBTaskRetryWithBackoffDefault = defaultRetryWithBackoffValue;
}

- (id)init {
    self = [super init];
    if (self) {
        self.userInfo = @{};
        self.createdDate = [NSDate date];
        self.availableDate = [NSDate date];
    }
    return self;
}

- (BOOL)canBeRetried {
    return self.maxRetries < 0 || self.retryCount < self.maxRetries;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"Task %@: %@ (%d retries, next available %@), userInfo: %@",
            self.taskID, self.name, self.retryCount, self.availableDate, self.userInfo];
}

@end
