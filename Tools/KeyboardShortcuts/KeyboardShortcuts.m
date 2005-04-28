// KeyboardShortcuts.m
// Kevin Ballard
//
// Copyright © 2005, Kevin Ballard

#import <Foundation/Foundation.h>

int main (int argc, const char * argv[]) {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	NSArray *sourcePaths = [NSArray arrayWithObjects:
		@"/Library/Application Support/TextMate/Bundles",
		[@"~/Library/Application Support/TextMate/Bundles" stringByExpandingTildeInPath],
		nil];
	NSArray *subPaths = [NSArray arrayWithObjects:@"Commands", @"Macros", @"Snippets", nil];
	NSFileManager *fm = [NSFileManager defaultManager];
	
	NSMutableDictionary *bundles = [NSMutableDictionary dictionary];
	
	// First gather the bundle information we want
	NSEnumerator *sourceEnum = [sourcePaths objectEnumerator];
	NSString *sourcePath;
	while( sourcePath = [sourceEnum nextObject] ) {
		NSArray *bundlePaths = [[fm directoryContentsAtPath:sourcePath]
									pathsMatchingExtensions:[NSArray arrayWithObject:@"tmbundle"]];
		NSEnumerator *bundleEnum = [bundlePaths objectEnumerator];
		NSString *bundlePath;
		while( bundlePath = [bundleEnum nextObject] ) {
			NSMutableDictionary *bundle = [NSMutableDictionary dictionary];
			NSDictionary *infoPlist = [NSDictionary dictionaryWithContentsOfFile:
				[[sourcePath stringByAppendingPathComponent:bundlePath]
					stringByAppendingPathComponent:@"info.plist"]];
			if( ! infoPlist )
				continue;
			
			NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
			NSEnumerator *subEnum = [subPaths objectEnumerator];
			NSString *subPath;
			while( subPath = [subEnum nextObject] ) {
				NSMutableArray *items = [NSMutableArray array];
				NSString *plistPath = [[sourcePath stringByAppendingPathComponent:bundlePath]
											stringByAppendingPathComponent:subPath];
				NSArray *plists = [[fm directoryContentsAtPath:plistPath]
										pathsMatchingExtensions:[NSArray arrayWithObject:@"plist"]];
				NSEnumerator *plistEnum = [plists objectEnumerator];
				NSString *plist;
				while( plist = [plistEnum nextObject] ) {
					NSString *path = [plistPath stringByAppendingPathComponent:plist];
					NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
					NSMutableDictionary *item = [NSMutableDictionary dictionary];
					[item setValue:[dict objectForKey:@"keyEquivalent"] forKey:@"keyEquivalent"];
					[item setValue:[dict objectForKey:@"tabTrigger"] forKey:@"tabTrigger"];
					[item setValue:[dict objectForKey:@"trigger"] forKey:@"trigger"];
					if( [item count] > 0 ) {
						[item setValue:[dict objectForKey:@"name"] forKey:@"name"];
						[items addObject:item];
					}
				}
				if( [items count] > 0 ) {
					[bundle setObject:items forKey:subPath];
				}
			}
			[innerPool release];
			
			if( [bundle count] > 0 ) {
				[bundle setObject:[infoPlist objectForKey:@"name"] forKey:@"name"];
				[bundle setObject:[infoPlist objectForKey:@"uuid"] forKey:@"uuid"];
				
				NSDictionary *oldBundle = [bundles objectForKey:[infoPlist objectForKey:@"uuid"]];
				if( oldBundle ) {
					NSMutableDictionary *newBundle = [oldBundle mutableCopy];
					[newBundle addEntriesFromDictionary:bundle];
					bundle = newBundle;
				}
				[bundles setObject:bundle forKey:[infoPlist objectForKey:@"uuid"]];
			}
		}
	}
	
	// Now output the bundles list as a property list
	NSString *errorStr = nil;
	NSData *data = [NSPropertyListSerialization dataFromPropertyList:[bundles allValues]
															  format:NSPropertyListXMLFormat_v1_0
													errorDescription:&errorStr];
	
	if( errorStr ) {
		NSFileHandle *errorHandle = [NSFileHandle fileHandleWithStandardError];
		[errorHandle writeData:[errorStr dataUsingEncoding:NSUTF8StringEncoding]];
		[pool release];
		return 1;
	}
	
	NSFileHandle *outputHandle = [NSFileHandle fileHandleWithStandardOutput];
	[outputHandle writeData:data];
	
	[pool release];
	return 0;
}
