#import "Lexicon.h"
#import <CoreFoundation/CoreFoundation.h>
#import <sqlite3.h>

@implementation EHEntry

- (NSString *)textForTraditional:(BOOL)traditional {
    if (!traditional) return self.simplified;
    if (self.traditionalOverride.length > 0) return self.traditionalOverride;
    NSMutableString *result = [self.simplified mutableCopy];
    CFStringTransform((__bridge CFMutableStringRef)result, NULL, CFSTR("Hans-Hant"), false);
    return result;
}

@end

@interface EHLexicon () {
    sqlite3 *_database;
    sqlite3_stmt *_exactStatement;
    sqlite3_stmt *_prefixStatement;
}
@end

@implementation EHLexicon

+ (instancetype)sharedLexicon {
    static EHLexicon *lexicon;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lexicon = [[EHLexicon alloc] init]; });
    return lexicon;
}

+ (NSString *)normalizedKey:(NSString *)input {
    NSString *lower = [[input lowercaseString] stringByReplacingOccurrencesOfString:@"-" withString:@" "];
    NSArray<NSString *> *parts = [lower componentsSeparatedByCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableArray<NSString *> *nonempty = [NSMutableArray array];
    for (NSString *part in parts) {
        if (part.length > 0) [nonempty addObject:part];
    }
    return [nonempty componentsJoinedByString:@" "];
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    NSURL *path = [[NSBundle mainBundle] URLForResource:@"lexicon" withExtension:@"sqlite3"];
    if (!path) {
        NSLog(@"EnglishHanZi: missing lexicon.sqlite3");
        return self;
    }
    int flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX;
    if (sqlite3_open_v2(path.fileSystemRepresentation, &_database, flags, NULL) != SQLITE_OK) {
        NSLog(@"EnglishHanZi: cannot open lexicon: %s", sqlite3_errmsg(_database));
        if (_database) sqlite3_close(_database);
        _database = NULL;
        return self;
    }
    sqlite3_busy_timeout(_database, 100);
    const char *exactSQL =
        "SELECT key, simplified, traditional, score, source FROM entries "
        "WHERE key = ? ORDER BY score DESC LIMIT ?";
    const char *prefixSQL =
        "SELECT key, simplified, traditional, score, source FROM entries "
        "WHERE key >= ? AND key < ? AND key != ? ORDER BY score DESC LIMIT ?";
    if (sqlite3_prepare_v2(_database, exactSQL, -1, &_exactStatement, NULL) != SQLITE_OK ||
        sqlite3_prepare_v2(_database, prefixSQL, -1, &_prefixStatement, NULL) != SQLITE_OK) {
        NSLog(@"EnglishHanZi: invalid lexicon: %s", sqlite3_errmsg(_database));
    }
    return self;
}

- (void)dealloc {
    if (_exactStatement) sqlite3_finalize(_exactStatement);
    if (_prefixStatement) sqlite3_finalize(_prefixStatement);
    if (_database) sqlite3_close(_database);
}

- (BOOL)isReady { return _exactStatement != NULL && _prefixStatement != NULL; }

- (EHEntry *)entryFromStatement:(sqlite3_stmt *)statement {
    EHEntry *entry = [[EHEntry alloc] init];
    entry.english = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(statement, 0)];
    entry.simplified = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(statement, 1)];
    const unsigned char *traditional = sqlite3_column_text(statement, 2);
    if (traditional) entry.traditionalOverride = [NSString stringWithUTF8String:(const char *)traditional];
    entry.score = sqlite3_column_int(statement, 3);
    entry.source = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(statement, 4)];
    return entry;
}

- (void)appendResultsFrom:(sqlite3_stmt *)statement
                toEntries:(NSMutableArray<EHEntry *> *)entries
                     seen:(NSMutableSet<NSString *> *)seen
              traditional:(BOOL)traditional
                    limit:(NSUInteger)limit {
    while (entries.count < limit && sqlite3_step(statement) == SQLITE_ROW) {
        EHEntry *entry = [self entryFromStatement:statement];
        NSString *text = [entry textForTraditional:traditional];
        if ([seen containsObject:text]) continue;
        [seen addObject:text];
        [entries addObject:entry];
    }
    sqlite3_reset(statement);
    sqlite3_clear_bindings(statement);
}

- (void)appendExact:(NSString *)key
          toEntries:(NSMutableArray<EHEntry *> *)entries
               seen:(NSMutableSet<NSString *> *)seen
        traditional:(BOOL)traditional
              limit:(NSUInteger)limit {
    sqlite3_bind_text(_exactStatement, 1, key.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_int(_exactStatement, 2, (int)limit);
    [self appendResultsFrom:_exactStatement toEntries:entries seen:seen traditional:traditional limit:limit];
}

- (NSArray<NSString *> *)fallbackKeys:(NSString *)key {
    NSMutableArray<NSString *> *variants = [NSMutableArray array];
    if ([key hasSuffix:@"ies"] && key.length > 4)
        [variants addObject:[[key substringToIndex:key.length - 3] stringByAppendingString:@"y"]];
    if ([key hasSuffix:@"ing"] && key.length > 5) {
        NSString *stem = [key substringToIndex:key.length - 3];
        [variants addObject:stem];
        [variants addObject:[stem stringByAppendingString:@"e"]];
        if (stem.length > 2 && [stem characterAtIndex:stem.length - 1] == [stem characterAtIndex:stem.length - 2])
            [variants addObject:[stem substringToIndex:stem.length - 1]];
    }
    if ([key hasSuffix:@"ed"] && key.length > 4) {
        NSString *stem = [key substringToIndex:key.length - 2];
        [variants addObject:stem];
        [variants addObject:[stem stringByAppendingString:@"e"]];
    }
    if ([key hasSuffix:@"es"] && key.length > 3)
        [variants addObject:[key substringToIndex:key.length - 2]];
    if ([key hasSuffix:@"s"] && key.length > 2)
        [variants addObject:[key substringToIndex:key.length - 1]];
    return variants;
}

- (NSArray<EHEntry *> *)lookup:(NSString *)input traditional:(BOOL)traditional limit:(NSUInteger)limit {
    if (!self.isReady || limit == 0) return @[];
    NSString *key = [EHLexicon normalizedKey:input];
    if (key.length == 0 || key.length > 64) return @[];
    NSMutableArray<EHEntry *> *entries = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    [self appendExact:key toEntries:entries seen:seen traditional:traditional limit:limit];
    if (entries.count == 0 && [key rangeOfString:@" "].location == NSNotFound) {
        for (NSString *fallback in [self fallbackKeys:key]) {
            [self appendExact:fallback toEntries:entries seen:seen traditional:traditional limit:limit];
            if (entries.count > 0) break;
        }
    }
    // Once a complete word exists, keep the candidate list about that word.
    // Prefix suggestions are only useful while the spelling is incomplete.
    if (key.length >= 2 && entries.count == 0) {
        NSString *end = [key stringByAppendingString:@"{"];
        sqlite3_bind_text(_prefixStatement, 1, key.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(_prefixStatement, 2, end.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(_prefixStatement, 3, key.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_int(_prefixStatement, 4, (int)(limit * 4));
        [self appendResultsFrom:_prefixStatement toEntries:entries seen:seen traditional:traditional limit:limit];
    }
    return entries;
}

@end
