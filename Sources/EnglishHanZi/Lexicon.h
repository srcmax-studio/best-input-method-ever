#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface EHEntry : NSObject
@property (nonatomic, copy) NSString *english;
@property (nonatomic, copy) NSString *simplified;
@property (nonatomic, copy, nullable) NSString *traditionalOverride;
@property (nonatomic, copy) NSString *source;
@property (nonatomic) NSInteger score;
- (NSString *)textForTraditional:(BOOL)traditional;
@end

@interface EHLexicon : NSObject
@property (nonatomic, readonly) BOOL isReady;
+ (instancetype)sharedLexicon;
+ (NSString *)normalizedKey:(NSString *)input;
- (NSArray<EHEntry *> *)lookup:(NSString *)input traditional:(BOOL)traditional limit:(NSUInteger)limit;
@end

NS_ASSUME_NONNULL_END
