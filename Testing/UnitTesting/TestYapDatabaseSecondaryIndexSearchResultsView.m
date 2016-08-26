//
//  TestYapDatabaseSecondaryIndexSearchResultsView.m
//  YapDatabaseTesting
//
//  Created by Raffi Senerol on 8/26/16.
//  Copyright © 2016 Robbie Hanson. All rights reserved.
//

#import <XCTest/XCTest.h>

#import "YapDatabase.h"
#import "YapDatabaseView.h"
#import "YapDatabaseSecondaryIndex.h"
#import "YapDatabaseSearchResultsView.h"
#import "YapCollectionKey.h"

#import "TestObject.h"

#import <CocoaLumberjack/CocoaLumberjack.h>
#import <CocoaLumberjack/DDTTYLogger.h>

@interface TestYapDatabaseSecondaryIndexSearchResultsView : XCTestCase
@end

@implementation TestYapDatabaseSecondaryIndexSearchResultsView

- (NSString *)databasePath:(NSString *)suffix
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *baseDir = ([paths count] > 0) ? [paths objectAtIndex:0] : NSTemporaryDirectory();
    
    NSString *databaseName = [NSString stringWithFormat:@"%@-%@.sqlite", THIS_FILE, suffix];
    
    return [baseDir stringByAppendingPathComponent:databaseName];
}

- (void)setUp
{
    [super setUp];
    [DDLog removeAllLoggers];
    [DDLog addLogger:[DDTTYLogger sharedInstance]];
}

- (void)tearDown
{
    [DDLog flushLog];
    [super tearDown];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Bad Init
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_badInit
{
    dispatch_block_t exceptionBlock = ^{
        
        YapDatabaseViewGrouping *grouping = [YapDatabaseViewGrouping withKeyBlock:
             ^NSString *(YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key)
         {
             if ([key isEqualToString:@"keyX"]) // Exclude keyX from view
                 return nil;
             else
                 return @"";
        }];
        
        YapDatabaseViewSorting *sorting = [YapDatabaseViewSorting withObjectBlock:
           ^(YapDatabaseReadTransaction *transaction, NSString *group,
             NSString *collection1, NSString *key1, id obj1,
             NSString *collection2, NSString *key2, id obj2)
        {
            __unsafe_unretained NSNumber *number1 = (NSNumber *)obj1;
            __unsafe_unretained NSNumber *number2 = (NSNumber *)obj2;
               
            return [number1 compare:number2];
        }];
        
        (void)[[YapDatabaseSearchResultsView alloc] initWithGrouping:grouping
                                                             sorting:sorting
                                                          versionTag:@"xyz"
                                                             options:nil];
    };
    
    XCTAssertThrows(exceptionBlock(), @"Should have thrown an exception");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark With ParentView
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test1_parentView_memory
{
    NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
    
    YapDatabaseSearchResultsViewOptions *searchViewOptions = [[YapDatabaseSearchResultsViewOptions alloc] init];
    searchViewOptions.isPersistent = NO;
    
    [self _test1_parentView_withPath:databasePath options:searchViewOptions];
}

- (void)test1_parentView_persistent
{
    NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
    
    YapDatabaseSearchResultsViewOptions *searchViewOptions = [[YapDatabaseSearchResultsViewOptions alloc] init];
    searchViewOptions.isPersistent = YES;
    
    [self _test1_parentView_withPath:databasePath options:searchViewOptions];
}

- (void)_test1_parentView_withPath:(NSString *)databasePath
                           options:(YapDatabaseSearchResultsViewOptions *)searchViewOptions
{
    [[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
    YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
    
    XCTAssertNotNil(database, @"Oops");
    
    // Setup ParentView
    //
    YapDatabaseViewGrouping *grouping = [YapDatabaseViewGrouping withKeyBlock:
        ^NSString *(YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key)
    {
        return @"";
    }];
    
    YapDatabaseViewSorting *sorting = [YapDatabaseViewSorting withObjectBlock:
        ^(YapDatabaseReadTransaction *transaction, NSString *group,
          NSString *collection1, NSString *key1, id obj1,
          NSString *collection2, NSString *key2, id obj2)
    {
        __unsafe_unretained NSString *str1 = [(TestObject *)obj1 someString];
        __unsafe_unretained NSString *str2 = [(TestObject *)obj2 someString];
       
        return [str1 compare:str2 options:NSLiteralSearch];
    }];
    
    YapDatabaseViewOptions *viewOptions = [[YapDatabaseViewOptions alloc] init];
    viewOptions.isPersistent = NO;
    
    YapDatabaseView *view =
    [[YapDatabaseView alloc] initWithGrouping:grouping
                                      sorting:sorting
                                   versionTag:@"1"
                                      options:viewOptions];
    
    BOOL registerResult1 = [database registerExtension:view withName:@"order"];
    XCTAssertTrue(registerResult1, @"Failure registering view extension");
    
    // Setup Secondary Index
    //
    YapDatabaseSecondaryIndexSetup *setup = [[YapDatabaseSecondaryIndexSetup alloc] init];
    [setup addColumn:@"someDate" withType:YapDatabaseSecondaryIndexTypeReal];
    [setup addColumn:@"someInt" withType:YapDatabaseSecondaryIndexTypeInteger];
    
    YapDatabaseSecondaryIndexHandler *handler = [YapDatabaseSecondaryIndexHandler withObjectBlock:
        ^(NSMutableDictionary *dict, NSString *collection, NSString *key, id object){
            
             // If we're storing other types of objects in our database,
             // then we should check the object before presuming we can cast it.
             if ([object isKindOfClass:[TestObject class]])
             {
                 __unsafe_unretained TestObject *testObject = (TestObject *)object;
                 
                 if (testObject.someDate)
                     [dict setObject:testObject.someDate forKey:@"someDate"];
                 
                 [dict setObject:@(testObject.someInt) forKey:@"someInt"];
             }
    }];
    
    YapDatabaseSecondaryIndex *secondaryIndex = [[YapDatabaseSecondaryIndex alloc] initWithSetup:setup handler:handler];
    
    [database registerExtension:secondaryIndex withName:@"idx"];
    
    // Setup SearchResultsView
    //
    YapDatabaseSearchResultsView *searchResultsView =
    [[YapDatabaseSearchResultsView alloc] initWithSecondaryIndexName:@"idx"
                                                      parentViewName:@"order" versionTag:@"1"
                                                             options:searchViewOptions];
    
    BOOL registerResult3 = [database registerExtension:searchResultsView withName:@"searchResults"];
    XCTAssertTrue(registerResult3, @"Failure registering searchResults extension");
    
    [self _testWithDatabase:database options:searchViewOptions];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark With Blocks
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test1_blocks_memory
{
    NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
    
    YapDatabaseSearchResultsViewOptions *searchViewOptions = [[YapDatabaseSearchResultsViewOptions alloc] init];
    searchViewOptions.isPersistent = NO;
    
    [self _test1_blocks_withPath:databasePath options:searchViewOptions];
}

- (void)test1_blocks_persistent
{
    NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
    
    YapDatabaseSearchResultsViewOptions *searchViewOptions = [[YapDatabaseSearchResultsViewOptions alloc] init];
    searchViewOptions.isPersistent = YES;
    
    [self _test1_blocks_withPath:databasePath options:searchViewOptions];
}

- (void)_test1_blocks_withPath:(NSString *)databasePath
                       options:(YapDatabaseSearchResultsViewOptions *)searchViewOptions
{
    [[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
    YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
    
    XCTAssertNotNil(database, @"Oops");
    
    // Setup Secondary Index
    YapDatabaseSecondaryIndexSetup *setup = [[YapDatabaseSecondaryIndexSetup alloc] init];
    [setup addColumn:@"someDate" withType:YapDatabaseSecondaryIndexTypeReal];
    [setup addColumn:@"someInt" withType:YapDatabaseSecondaryIndexTypeInteger];
    
    YapDatabaseSecondaryIndexHandler *handler = [YapDatabaseSecondaryIndexHandler withObjectBlock:
        ^(NSMutableDictionary *dict, NSString *collection, NSString *key, id object){
         
         // If we're storing other types of objects in our database,
         // then we should check the object before presuming we can cast it.
         if ([object isKindOfClass:[TestObject class]])
         {
             __unsafe_unretained TestObject *testObject = (TestObject *)object;
             
             if (testObject.someDate)
                 [dict setObject:testObject.someDate forKey:@"someDate"];
             
             [dict setObject:@(testObject.someInt) forKey:@"someInt"];
         }
     }];

    YapDatabaseSecondaryIndex *secondaryIndex = [[YapDatabaseSecondaryIndex alloc] initWithSetup:setup handler:handler versionTag:@"1"];
    
    BOOL registerResult1 = [database registerExtension:secondaryIndex withName:@"idx"];
    XCTAssertTrue(registerResult1, @"Failure registering fts extension");
    
    // Setup SearchResultsView
    //
    YapDatabaseViewGrouping *grouping = [YapDatabaseViewGrouping withKeyBlock:
        ^NSString *(YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key)
     {
         return @"";
     }];
    
    YapDatabaseViewSorting *sorting = [YapDatabaseViewSorting withObjectBlock:
        ^(YapDatabaseReadTransaction *transaction, NSString *group, NSString *collection1, NSString *key1, id obj1, NSString *collection2, NSString *key2, id obj2)
   {
       __unsafe_unretained NSString *str1 = [(TestObject *)obj1 someString];
       __unsafe_unretained NSString *str2 = [(TestObject *)obj2 someString];
       
       return [str1 compare:str2 options:NSLiteralSearch];
   }];
    
    YapDatabaseSearchResultsView *searchResultsView =
    [[YapDatabaseSearchResultsView alloc] initWithSecondaryIndexName:@"idx"
                                                            grouping:grouping
                                                             sorting:sorting
                                                          versionTag:@"1"
                                                             options:searchViewOptions];
    
    BOOL registerResult2 = [database registerExtension:searchResultsView withName:@"searchResults"];
    XCTAssertTrue(registerResult2, @"Failure registering searchResults extension");
    
    [self _testWithDatabase:database options:searchViewOptions];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Test Logic
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)_testWithDatabase:(YapDatabase *)database options:(YapDatabaseSearchResultsViewOptions *)searchViewOptions
{
    YapDatabaseConnection *connection1 = [database newConnection];
    YapDatabaseConnection *connection2 = [database newConnection];
    
    connection1.name = @"connection1";
    connection2.name = @"connection2";
    
    // Populating the database
    //
    NSDate *startDate = [NSDate date];
    int startInt = 0;

    [connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        for (int i = 0; i < 20; i++)
        {
            NSDate *someDate = [startDate dateByAddingTimeInterval:i];
            int someInt = startInt + i;
            
            TestObject *object = [TestObject generateTestObjectWithSomeDate:someDate someInt:someInt];
            
            NSString *key = [NSString stringWithFormat:@"key%d", i];
            
            [transaction setObject:object forKey:key inCollection:nil];
        }
        
        NSUInteger count = [[transaction ext:@"searchResults"] numberOfItemsInGroup:@""];
        XCTAssertTrue(count == 20, @"Bad count: %lu", (unsigned long)count);
    }];
    
    YapDatabaseQuery *query = nil;

    // Test basic queries
    //
    query = [YapDatabaseQuery queryMatchingAll];
    [self testQuery:query withConnection:connection1 andExpectedResults:20];
    [self testQuery:query withConnection:connection2 andExpectedResults:20];
    
    query = [YapDatabaseQuery queryWithFormat:@"WHERE someInt < 5"];
    [self testQuery:query withConnection:connection1 andExpectedResults:5];
    [self testQuery:query withConnection:connection2 andExpectedResults:5];
    
    query = [YapDatabaseQuery queryWithFormat:@"WHERE someInt < ?", @(5)];
    [self testQuery:query withConnection:connection1 andExpectedResults:5];
    [self testQuery:query withConnection:connection2 andExpectedResults:5];
    
    query = [YapDatabaseQuery queryWithFormat:@"WHERE someDate < ?", [startDate dateByAddingTimeInterval:3]];
    [self testQuery:query withConnection:connection1 andExpectedResults:3];
    [self testQuery:query withConnection:connection2 andExpectedResults:3];
    
    // Test basic queries after updating the database
    //
    startDate = [NSDate dateWithTimeIntervalSinceNow:4];
    startInt = 100;
    
    [connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        for (int i = 0; i < 20; i++)
        {
            NSDate *someDate = [startDate dateByAddingTimeInterval:i];
            int someInt = startInt + i;
            
            TestObject *object = [TestObject generateTestObjectWithSomeDate:someDate someInt:someInt];
            
            NSString *key = [NSString stringWithFormat:@"key%d", i];
            
            [transaction setObject:object forKey:key inCollection:nil];
        }
    }];
    
    query = [YapDatabaseQuery queryMatchingAll];
    [self testQuery:query withConnection:connection1 andExpectedResults:20];
    [self testQuery:query withConnection:connection2 andExpectedResults:20];
    
    query = [YapDatabaseQuery queryWithFormat:@"WHERE someInt < 110"];
    [self testQuery:query withConnection:connection1 andExpectedResults:10];
    [self testQuery:query withConnection:connection2 andExpectedResults:10];
    
    query = [YapDatabaseQuery queryWithFormat:@"WHERE someInt < ?", @(110)];
    [self testQuery:query withConnection:connection1 andExpectedResults:10];
    [self testQuery:query withConnection:connection2 andExpectedResults:10];
    
    // Test basic queries after adding new objects
    //
    startInt = 100;
    
    [connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        for (int i = 20; i < 40; i++)
        {
            NSDate *someDate = [startDate dateByAddingTimeInterval:i];
            int someInt = startInt + i;
            
            TestObject *object = [TestObject generateTestObjectWithSomeDate:someDate someInt:someInt];
            
            NSString *key = [NSString stringWithFormat:@"key%d", i];
            
            [transaction setObject:object forKey:key inCollection:nil];
        }
    }];
    
    query = [YapDatabaseQuery queryMatchingAll];
    [self testQuery:query withConnection:connection1 andExpectedResults:40];
    [self testQuery:query withConnection:connection2 andExpectedResults:40];
    
    query = [YapDatabaseQuery queryWithFormat:@"WHERE someInt >= 120"];
    [self testQuery:query withConnection:connection1 andExpectedResults:20];
    [self testQuery:query withConnection:connection2 andExpectedResults:20];
    
    query = [YapDatabaseQuery queryWithFormat:@"WHERE someInt >= ?", @(120)];
    [self testQuery:query withConnection:connection1 andExpectedResults:20];
    [self testQuery:query withConnection:connection2 andExpectedResults:20];
    
    // Test basic queries after removing all objects
    //
    [connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction removeAllObjectsInAllCollections];
    }];
    
    query = [YapDatabaseQuery queryMatchingAll];
    [self testQuery:query withConnection:connection1 andExpectedResults:0];
    [self testQuery:query withConnection:connection2 andExpectedResults:0];
    
    query = [YapDatabaseQuery queryWithFormat:@"WHERE someInt >= 120"];
    [self testQuery:query withConnection:connection1 andExpectedResults:0];
    [self testQuery:query withConnection:connection2 andExpectedResults:0];
    
    query = [YapDatabaseQuery queryWithFormat:@"WHERE someInt >= ?", @(120)];
    [self testQuery:query withConnection:connection1 andExpectedResults:0];
    [self testQuery:query withConnection:connection2 andExpectedResults:0];
}

- (void)testQuery:(YapDatabaseQuery*)query withConnection:(YapDatabaseConnection *)connection andExpectedResults:(NSUInteger)expectedQueryResults
{
    [connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        
        [[transaction ext:@"searchResults"] performSecondaryIndexSearchFor:query];
        
        NSUInteger count = [[transaction ext:@"searchResults"] numberOfItemsInGroup:@""];
        XCTAssertTrue(count == expectedQueryResults, @"Bad count: %lu, query: %@", (unsigned long)count, query.queryString);
    }];
    
    [connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        
        NSString *connectionQuery = [[transaction ext:@"searchResults"] indexQuery].queryString;
        XCTAssertTrue([connectionQuery isEqualToString:query.queryString], @"Bad connection query: %@", connectionQuery);
    }];
}

@end
