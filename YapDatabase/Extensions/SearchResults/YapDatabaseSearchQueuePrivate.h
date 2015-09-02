#import "YapDatabaseSearchQueue.h"

/**
 * This header file is PRIVATE, and is only to be used by the YapDatabaseSearchResultsTransaction class.
**/

@interface YapDatabaseSearchQueue ()

- (id)flushQueue;

- (BOOL)shouldAbortSearchInProgressAndRollback:(BOOL *)shouldRollbackPtr;

@end
