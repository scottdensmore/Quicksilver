#import "QSObject_Pasteboard.h"
#import "QSTypes.h"
#import "QSObject_FileHandling.h"
#import "QSObject_StringHandling.h"

NSString *QSPasteboardObjectIdentifier = @"QSObjectID";
NSString *QSPasteboardObjectAddress = @"QSObjectAddress";

#define QSPasteboardIgnoredTypes [NSArray arrayWithObjects:QSPasteboardObjectAddress, @"CorePasteboardFlavorType 0x4D555246", @"CorePasteboardFlavorType 0x54455854", nil]

id objectForPasteboardType(NSPasteboard *pasteboard, NSString *type) {
	if ([PLISTTYPES containsObject:type]) {
		return [pasteboard propertyListForType:type];
	}
	if ([NSStringPboardType isEqualToString:type] || UTTypeConformsTo((__bridge CFStringRef)type, kUTTypeText) || [type hasPrefix:@"QSObject"]) {
		if ([pasteboard stringForType:type]) {
			return [pasteboard stringForType:type];
		}
	}

	if ([NSURLPboardType isEqualToString:type]) {
		return [[NSURL URLFromPasteboard:pasteboard] absoluteString];
    }
	if ([(__bridge NSString *)kUTTypeFileURL isEqualToString:type]) {
        return [NSURL URLFromPasteboard:pasteboard];
    }
	if ([NSColorPboardType isEqualToString:type]) {
		return [NSKeyedArchiver archivedDataWithRootObject:[NSColor colorFromPasteboard:pasteboard]];
	}
//	fallback - return it as data
	return [pasteboard dataForType:type];
}

@implementation QSObject (Pasteboard)


+ (id)objectWithPasteboard:(NSPasteboard *)pasteboard {
	id theObject = nil;

	if ([NSPasteboard isPasteboardTransient:pasteboard]
        || [NSPasteboard isPasteboardAutoGenerated:pasteboard]
        || [NSPasteboard isPasteboardConcealed:pasteboard])
		return nil;

	if ([[pasteboard types] containsObject:QSPasteboardObjectIdentifier])
		theObject = [QSLib objectWithIdentifier:[pasteboard stringForType:QSPasteboardObjectIdentifier]];
    
    if (theObject) {
        return theObject;
    }
    return [[QSObject alloc] initWithPasteboard:pasteboard];
}

- (NSArray<NSString *> *) writableTypesForPasteboard:(NSPasteboard *) pasteboard {
	NSMutableArray *types = [[NSMutableArray alloc] init];
	if ([self validPaths]) {
		[types addObject:kUTTypeFileURL];
	} else {
		
		[types addObjectsFromArray:[[self dataDictionary] allKeys]];
		if ([types containsObject:QSProxyType]) {
			[types addObjectsFromArray:[[[self resolvedObject] dataDictionary] allKeys]];
		}
		
		if ([types count] == 0) {
			[types addObject:NSStringPboardType];
		}
		if ([types containsObject:NSURLPboardType]) {
			[types addObjectsFromArray:@[NSURLPboardType,NSHTMLPboardType,NSRTFPboardType,NSStringPboardType]];
		}
	}
	[types addObjectsFromArray:@[QSPasteboardObjectIdentifier, QSPasteboardObjectAddress]];
	return types;
}

- (NSPasteboardWritingOptions) writingOptionsForType:(NSPasteboardType) type
										  pasteboard:(NSPasteboard *) pasteboard {
	return NSPasteboardWritingPromised;
}

- (id) pasteboardPropertyListForType:(NSPasteboardType) type {
	if ([type isEqualToString:QSPasteboardObjectAddress]) {
		QSLib.pasteboardObject = self;
		return [NSString stringWithFormat:@"copied object at %p", self];
	}
	
	
	id pbData = nil;
	id handler = [self handlerForType:type selector:@selector(dataForObject:pasteboardType:)];
	if (handler) {
		pbData = [handler dataForObject:self pasteboardType:type];
	} else {
		pbData = [self objectForType:type];
	}
	
	if ([type isEqualToString:@"public.file-url"]) {
		return [[NSURL fileURLWithPath:[self validPaths][0]] pasteboardPropertyListForType:type];
	}
	
	if ([type isEqualToString:QSPasteboardObjectIdentifier]) {
		return [self identifier];
	}
	
	if ([type isEqualToString:NSHTMLPboardType]) {
		return [NSString dataForObject:self forType:NSHTMLPboardType];
	}
	if ([type isEqualToString:NSRTFPboardType]) {
		return [NSString dataForObject:self forType:NSRTFPboardType];
	}
	if ([type isEqualToString:NSURLPboardType]) {
		return [pbData hasPrefix:@"mailto:"] ? [pbData substringFromIndex:7] : pbData;
	}
	if ([PLISTTYPES containsObject:type] || [pbData isKindOfClass:[NSDictionary class]] || [pbData isKindOfClass:[NSArray class]]) {
		if (![pbData isKindOfClass:[NSArray class]]) {
			return @[pbData];
		}
	}
	return pbData;
}


- (id)initWithPasteboard:(NSPasteboard *)pasteboard {
    return [self initWithPasteboard:pasteboard types:nil];
}

- (void)addContentsOfClipping:(NSString *)path {
    NSPasteboard *pasteboard = [NSPasteboard pasteboardByFilteringClipping:path];
}

- (void)addContentsOfPasteboard:(NSPasteboard *)pasteboard types:(NSArray *)types {
	for(NSString *thisType in (types?types:[pasteboard types])) {
		if ([[pasteboard types] containsObject:thisType] && ![QSPasteboardIgnoredTypes containsObject:thisType]) {
			id theObject = objectForPasteboardType(pasteboard, thisType);
			if (theObject && thisType) {
				[self setObject:theObject forType:thisType];
            } else {
				NSLog(@"bad data for %@", thisType);
            }
		}
	}
}

- (id)initWithPasteboard:(NSPasteboard *)pasteboard types:(NSArray *)types {
	if (self = [self init]) {

		NSString *source = nil;
        NSString *sourceApp = nil;
        NSRunningApplication *currApp = [[NSWorkspace sharedWorkspace] frontmostApplication];
		if (pasteboard == [NSPasteboard generalPasteboard]) {
			source = [currApp bundleIdentifier];
            sourceApp = [currApp localizedName];
        } else {
            source =  @"Clipboard";
            sourceApp = source;
        }
        [data removeAllObjects];
		[self addContentsOfPasteboard:pasteboard types:types];

		[self setObject:source forMeta:kQSObjectSource];
		[self setObject:[NSDate date] forMeta:kQSObjectCreationDate];

		id value;
		if (value = [self objectForType:NSRTFPboardType]) {
			value = [[NSAttributedString alloc] initWithRTF:value documentAttributes:nil];
			[self setObject:[value string] forType:QSTextType];
		}
		if ([self objectForType:QSTextType])
			[self sniffString];

		if ([self isClipping]) {
				[self addContentsOfClipping:[self singleFilePath]];
		}

		if ([self objectForType:kQSObjectPrimaryName])
			[self setName:[self objectForType:kQSObjectPrimaryName]];
		else {
			[self guessName];
		}
        if (![self name]) {
            if ([self objectForType:QSTextType]) {
                [self setName:[self objectForType:QSTextType]];
            } else {
                [self setName:NSLocalizedString(@"Unknown Clipboard Object", @"Name for an unknown clipboard object")];
            }
            [self setDetails:[NSString stringWithFormat:NSLocalizedString(@"Unknown type from %@",@"Details of unknown clipboard objects. Of the form 'Unknown type from Application'. E.g. 'Unknown type from Microsoft Word'"),sourceApp]];

        }
		[self loadIcon];
	}
	return self;
}
+ (id)objectWithClipping:(NSString *)clippingFile {
	return [[QSObject alloc] initWithClipping:clippingFile];
}
- (id)initWithClipping:(NSString *)clippingFile {
	NSPasteboard *pasteboard = [NSPasteboard pasteboardByFilteringClipping:clippingFile];
	if (self = [self initWithPasteboard:pasteboard]) {
		[self setLabel:[clippingFile lastPathComponent]];
	}
	[pasteboard releaseGlobally];
	return self;
}

- (void)guessName {
	if (itemForKey(QSFilePathType) ) {
		[self setPrimaryType:QSFilePathType];
		[self getNameFromFiles];
	} else {
        NSString *textString = itemForKey(QSTextType);
        // some objects (images from the web) don't have a text string but have a URL
        if (!textString) {
            textString = itemForKey(NSURLPboardType);
        }
        textString = [textString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		
		static NSDictionary *namesAndKeys = nil;
        static NSArray *keys = nil;
        if (!keys) {
            // Use an array for the keys since the order is important
            keys = [NSArray arrayWithObjects:[@"'icns'" encodedPasteboardType],NSPostScriptPboardType,NSTIFFPboardType,NSColorPboardType,NSFileContentsPboardType,NSFontPboardType,NSPasteboardTypeRTF,NSHTMLPboardType,NSRulerPboardType,NSTabularTextPboardType,NSVCardPboardType,NSFilesPromisePboardType,NSPDFPboardType,QSTextType,nil];

        }
        if (!namesAndKeys) {
            namesAndKeys = [NSDictionary dictionaryWithObjectsAndKeys:
                                      NSLocalizedString(@"PDF Image", @"Name of PDF image "),                               NSPDFPboardType,
                                      NSLocalizedString(@"PNG Image", @"Name of a PNG image object"),
                                      NSPasteboardTypePNG,
                                      NSLocalizedString(@"RTF Text", @"Name of a RTF text object"),
                                      NSPasteboardTypeRTF,
                                      NSLocalizedString(@"Finder Icon", @"Name of icon file object"),                       [@"'icns'" encodedPasteboardType],
                                      NSLocalizedString(@"PostScript Image", @"Name of PostScript image object"),           NSPostScriptPboardType,
                                      NSLocalizedString(@"TIFF Image", @"Name of TIFF image object"),                       NSTIFFPboardType,
                                      NSLocalizedString(@"Color Data", @"Name of Color data object"),                       NSColorPboardType,
                                      NSLocalizedString(@"File Contents", @"Name of File contents object"),                 NSFileContentsPboardType,
                                      NSLocalizedString(@"Font Information", @"Name of Font information object"),           NSFontPboardType,
                                      NSLocalizedString(@"HTML Data", @"Name of HTML data object"),                         NSHTMLPboardType,
                                      NSLocalizedString(@"Paragraph Formatting", @"Name of Paragraph Formatting object"),   NSRulerPboardType,
                                      NSLocalizedString(@"Tabular Text", @"Name of Tabular text object"),                   NSTabularTextPboardType,
                                      NSLocalizedString(@"VCard Data", @"Name of VCard data object"),                       NSVCardPboardType,
                                      NSLocalizedString(@"Promised Files", @"Name of Promised files object"),               NSFilesPromisePboardType,
                                      nil];
        }

        for (NSString *key in keys) {
			if (itemForKey(key) ) {
                if ([key isEqualToString:QSTextType]) {
                    [self setDetails:nil];
                } else {
                    [self setDetails:[namesAndKeys objectForKey:key]];
                }
                [self setPrimaryType:key];
                [self setName:textString];
                break;
            }
		}
	}
}

- (BOOL)putOnPasteboardAsPlainTextOnly:(NSPasteboard *)pboard {
	QSObject *plainTextObject = [QSObject objectWithString:[self stringValue]];
	[pboard clearContents];
	[pboard writeObjects:@[plainTextObject]];
	return YES;
}

- (BOOL)putOnPasteboard:(NSPasteboard *)pboard {
	[pboard clearContents];
	[pboard writeObjects:[self splitObjects]];
	return YES;
}

- (NSData *)dataForType:(NSString *)dataType {
	id theData = [data objectForKey:dataType];
	if ([theData isKindOfClass:[NSData class]]) return theData;
	return nil;
}
@end
