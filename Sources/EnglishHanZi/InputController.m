#import "InputController.h"
#import "Lexicon.h"
#import <Carbon/Carbon.h>

static NSString *const EHTraditionalKey = @"TraditionalChinese";
static NSString *const EHDirectEnglishKey = @"DirectEnglish";
static NSString *const EHSelectionHistoryKey = @"SelectionHistory";

@interface EnglishHanZiController () {
    NSMutableString *_composition;
    NSArray<EHEntry *> *_entries;
    NSArray<NSString *> *_candidateLabels;
    IMKCandidates *_candidateWindow;
    NSUInteger _selectedIndex;
    BOOL _traditional;
    BOOL _directEnglish;
}
@end

@implementation EnglishHanZiController

- (instancetype)initWithServer:(IMKServer *)server delegate:(id)delegate client:(id)inputClient {
    self = [super initWithServer:server delegate:delegate client:inputClient];
    if (!self) return nil;
    _composition = [NSMutableString string];
    _entries = @[];
    _candidateLabels = @[];
    _selectedIndex = 0;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    _traditional = [defaults objectForKey:EHTraditionalKey] ? [defaults boolForKey:EHTraditionalKey] : YES;
    _directEnglish = [defaults boolForKey:EHDirectEnglishKey];
    _candidateWindow = [[IMKCandidates alloc] initWithServer:server
                                                   panelType:kIMKSingleColumnScrollingCandidatePanel
                                                   styleType:kIMKMain];
    [_candidateWindow setAttributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:17],
        IMKCandidatesSendServerKeyEventFirst: @YES,
    }];
    return self;
}

- (void)activateServer:(id)sender {
    [super activateServer:sender];
    _traditional = [[NSUserDefaults standardUserDefaults] boolForKey:EHTraditionalKey];
    if (![[NSUserDefaults standardUserDefaults] objectForKey:EHTraditionalKey]) _traditional = YES;
    _directEnglish = [[NSUserDefaults standardUserDefaults] boolForKey:EHDirectEnglishKey];
}

- (void)deactivateServer:(id)sender {
    [_candidateWindow hide];
    if (_composition.length > 0) [self commitBestCandidate];
    [super deactivateServer:sender];
}

- (void)inputControllerWillClose {
    [_candidateWindow hide];
    [super inputControllerWillClose];
}

- (NSString *)historyKeyForEntry:(EHEntry *)entry {
    return [NSString stringWithFormat:@"%@\t%@", entry.english, entry.simplified];
}

- (void)recordSelection:(EHEntry *)entry {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *history = [[defaults dictionaryForKey:EHSelectionHistoryKey] mutableCopy];
    if (!history) history = [NSMutableDictionary dictionary];
    NSString *key = [self historyKeyForEntry:entry];
    history[key] = @([history[key] integerValue] + 1);
    // This is local selection history, with a fixed bound for long-term use.
    if (history.count > 4000) [history removeAllObjects];
    [defaults setObject:history forKey:EHSelectionHistoryKey];
}

- (void)refreshCandidates {
    if (_composition.length == 0) {
        _entries = @[];
        _candidateLabels = @[];
        [_candidateWindow hide];
        [self updateComposition];
        return;
    }
    NSArray<EHEntry *> *results = [[EHLexicon sharedLexicon] lookup:_composition
                                                          traditional:_traditional limit:9];
    NSDictionary *history = [[NSUserDefaults standardUserDefaults] dictionaryForKey:EHSelectionHistoryKey] ?: @{};
    NSString *query = [EHLexicon normalizedKey:_composition];
    _entries = [results sortedArrayUsingComparator:^NSComparisonResult(EHEntry *a, EHEntry *b) {
        BOOL aExact = [a.english isEqualToString:query];
        BOOL bExact = [b.english isEqualToString:query];
        if (aExact != bExact) return aExact ? NSOrderedAscending : NSOrderedDescending;
        NSInteger aScore = a.score + [history[[self historyKeyForEntry:a]] integerValue] * 10000;
        NSInteger bScore = b.score + [history[[self historyKeyForEntry:b]] integerValue] * 10000;
        if (aScore != bScore) return aScore > bScore ? NSOrderedAscending : NSOrderedDescending;
        return [a.english compare:b.english];
    }];
    NSMutableArray<NSString *> *labels = [NSMutableArray arrayWithCapacity:_entries.count];
    for (EHEntry *entry in _entries) {
        NSString *chinese = [entry textForTraditional:_traditional];
        if ([entry.english isEqualToString:query]) [labels addObject:chinese];
        else [labels addObject:[NSString stringWithFormat:@"%@ · %@", chinese, entry.english]];
    }
    _candidateLabels = labels;
    _selectedIndex = 0;
    [self updateComposition];
    if (_entries.count > 0) {
        [_candidateWindow updateCandidates];
        [_candidateWindow show:kIMKLocateCandidatesBelowHint];
        [self highlightSelectedCandidate];
    } else {
        [_candidateWindow hide];
    }
}

- (void)clearComposition {
    [_candidateWindow hide];
    [_composition setString:@""];
    _entries = @[];
    _candidateLabels = @[];
    _selectedIndex = 0;
}

- (void)highlightSelectedCandidate {
    if (_selectedIndex >= _candidateLabels.count) return;
    NSInteger identifier = [_candidateWindow candidateStringIdentifier:_candidateLabels[_selectedIndex]];
    if (identifier != NSNotFound) [_candidateWindow selectCandidateWithIdentifier:identifier];
}

- (void)commitText:(NSString *)text entry:(EHEntry *)entry {
    if (entry) [self recordSelection:entry];
    [self clearComposition];
    [[self client] insertText:text replacementRange:NSMakeRange(NSNotFound, NSNotFound)];
}

- (void)commitRawWithSpace:(BOOL)space {
    if (_composition.length == 0) return;
    NSString *raw = [_composition copy];
    if (space) raw = [raw stringByAppendingString:@" "];
    [self commitText:raw entry:nil];
}

- (void)commitEntryAtIndex:(NSUInteger)index {
    if (index >= _entries.count) return;
    EHEntry *entry = _entries[index];
    [self commitText:[entry textForTraditional:_traditional] entry:entry];
}

- (void)commitBestCandidate {
    if (_composition.length == 0) return;
    if (_entries.count == 0) {
        [self commitRawWithSpace:NO];
        return;
    }
    [self commitEntryAtIndex:MIN(_selectedIndex, _entries.count - 1)];
}

- (BOOL)handleEvent:(NSEvent *)event client:(id)sender {
    if (event.type != NSEventTypeKeyDown) return NO;
    NSEventModifierFlags modifiers = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    BOOL command = (modifiers & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption)) != 0;
    NSInteger key = event.keyCode;

    // Shift-Space toggles pass-through English without changing the system input source.
    if (key == kVK_Space && !command && (modifiers & NSEventModifierFlagShift)) {
        if (_composition.length > 0) [self commitRawWithSpace:NO];
        _directEnglish = !_directEnglish;
        [[NSUserDefaults standardUserDefaults] setBool:_directEnglish forKey:EHDirectEnglishKey];
        return YES;
    }
    if (_directEnglish) return NO;
    if (command) {
        if (_composition.length > 0) [self commitBestCandidate];
        return NO;
    }
    if (key == kVK_Delete || key == kVK_ForwardDelete) {
        if (_composition.length == 0) return NO;
        [_composition deleteCharactersInRange:NSMakeRange(_composition.length - 1, 1)];
        [self refreshCandidates];
        return YES;
    }
    if (key == kVK_Escape) {
        if (_composition.length == 0) return NO;
        [self commitRawWithSpace:NO];
        return YES;
    }
    if (key == kVK_Space || key == kVK_Return || key == kVK_ANSI_KeypadEnter) {
        if (_composition.length == 0) return NO;
        if (_entries.count > 0) [self commitBestCandidate];
        else [self commitRawWithSpace:key == kVK_Space];
        return YES;
    }
    if (key == kVK_Tab) {
        if (_composition.length == 0) return NO;
        [self commitRawWithSpace:NO];
        return YES;
    }
    if (key == kVK_UpArrow || key == kVK_DownArrow) {
        if (_entries.count == 0) return NO;
        if (key == kVK_DownArrow) _selectedIndex = (_selectedIndex + 1) % _entries.count;
        else _selectedIndex = (_selectedIndex + _entries.count - 1) % _entries.count;
        [self highlightSelectedCandidate];
        return YES;
    }
    if (key == kVK_LeftArrow || key == kVK_RightArrow) return NO;

    NSString *character = event.charactersIgnoringModifiers ?: @"";
    if (character.length != 1) {
        if (_composition.length > 0) [self commitBestCandidate];
        return NO;
    }
    unichar value = [character characterAtIndex:0];
    if (_composition.length > 0 && value >= '1' && value <= '9') {
        NSUInteger index = value - '1';
        if (index < _entries.count) {
            [self commitEntryAtIndex:index];
            return YES;
        }
        [self commitBestCandidate];
        return NO;
    }
    if (_composition.length > 0 && value == '0') {
        [self commitRawWithSpace:NO];
        return YES;
    }
    BOOL latinLetter = (value >= 'a' && value <= 'z') || (value >= 'A' && value <= 'Z');
    BOOL joiner = (value == '-' || value == '\'') && _composition.length > 0;
    if (latinLetter || joiner) {
        if (_composition.length >= 64) return YES;
        [_composition appendString:[[NSString stringWithCharacters:&value length:1] lowercaseString]];
        [self refreshCandidates];
        return YES;
    }
    if (_composition.length > 0) [self commitBestCandidate];
    return NO;
}

- (id)composedString:(id)sender { return [_composition copy]; }

- (NSAttributedString *)originalString:(id)sender {
    return [[NSAttributedString alloc] initWithString:_composition];
}

- (void)commitComposition:(id)sender { [self commitBestCandidate]; }

- (NSArray *)candidates:(id)sender { return _candidateLabels; }

- (void)candidateSelected:(NSAttributedString *)candidateString {
    NSString *selected = candidateString.string;
    NSUInteger index = [_candidateLabels indexOfObject:selected];
    if (index != NSNotFound) [self commitEntryAtIndex:index];
}

- (void)candidateSelectionChanged:(NSAttributedString *)candidateString {
    NSUInteger index = [_candidateLabels indexOfObject:candidateString.string];
    if (index != NSNotFound) _selectedIndex = index;
}

- (void)hidePalettes { [_candidateWindow hide]; }

- (NSMenu *)menu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"英译中文"];
    NSMenuItem *script = [[NSMenuItem alloc] initWithTitle:(_traditional ? @"切换为简体中文" : @"切換為繁體中文")
                                                 action:@selector(toggleTraditional:) keyEquivalent:@""];
    [menu addItem:script];
    NSMenuItem *mode = [[NSMenuItem alloc] initWithTitle:(_directEnglish ? @"切换为中文转换" : @"切换为直接英文")
                                               action:@selector(toggleDirectEnglish:) keyEquivalent:@""];
    [menu addItem:mode];
    return menu;
}

- (void)toggleTraditional:(id)sender {
    _traditional = !_traditional;
    [[NSUserDefaults standardUserDefaults] setBool:_traditional forKey:EHTraditionalKey];
    [self refreshCandidates];
}

- (void)toggleDirectEnglish:(id)sender {
    if (_composition.length > 0) [self commitRawWithSpace:NO];
    _directEnglish = !_directEnglish;
    [[NSUserDefaults standardUserDefaults] setBool:_directEnglish forKey:EHDirectEnglishKey];
}

@end
