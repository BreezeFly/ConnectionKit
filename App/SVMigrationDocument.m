//
//  SVMigrationDocument.m
//  Sandvox
//
//  Created by Mike on 17/02/2011.
//  Copyright 2011 Karelia Software. All rights reserved.
//

#import "SVMigrationDocument.h"

#import "SVMediaGraphic.h"
#import "SVMigrationManager.h"
#import "KT.h"


@implementation SVMigrationDocument

- (BOOL)migrate:(NSError **)outError;
{
    if (![self saveToURL:[self fileURL] ofType:kSVDocumentTypeName forSaveOperation:NSSaveOperation error:outError]) return NO;
    return YES;
    return [self readFromURL:[self fileURL] ofType:[self fileType] error:outError];
}

- (id)initWithContentsOfURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError **)outError;
{
    if (self = [super initWithContentsOfURL:absoluteURL ofType:typeName error:outError])
    {
        // Kick off migration in background
        NSOperationQueue *queue = [[NSOperationQueue alloc] init];
        
        NSOperation *operation = [[NSInvocationOperation alloc] initWithTarget:self
                                                                      selector:@selector(migrate:)
                                                                        object:nil];
        
        [queue addOperation:operation];
        [operation release];
    }
    return self;
}

- (BOOL)readFromURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError **)outError
{
    if ([typeName isEqualToString:kSVDocumentTypeName_1_5])
    {
        return YES;
        return [self migrate:NULL];
    }
    else
    {
        return [super readFromURL:absoluteURL ofType:typeName error:outError];
    }
}

- (BOOL)writeToURL:(NSURL *)inURL 
            ofType:(NSString *)inType 
  forSaveOperation:(NSSaveOperationType)saveOperation
originalContentsURL:(NSURL *)inOriginalContentsURL
             error:(NSError **)outError;
{
    // Only want special behaviour when doing a migration
    if (![[self fileType] isEqualToString:kSVDocumentTypeName_1_5])
    {
        return [super writeToURL:inURL ofType:inType forSaveOperation:saveOperation originalContentsURL:inOriginalContentsURL error:outError];
    }
    
    
    // Create directory to act as new document
    NSDictionary *attributes = [self fileAttributesToWriteToURL:inURL
                                                         ofType:inType
                                               forSaveOperation:saveOperation
                                            originalContentsURL:inOriginalContentsURL
                                                          error:outError];
    if (!attributes) return NO;
    
    NSFileManager *fileManager = [[[NSFileManager alloc] init] autorelease];    // likely to run on worker thread
    if (![fileManager createDirectoryAtPath:[inURL path]
                withIntermediateDirectories:NO
                                 attributes:attributes
                                      error:outError]) return NO;
                                                                                                                         
                                                                                                                         
    // Migrate!
    NSURL *modelURL = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"Sandvox 1.5" ofType:@"mom"]];
    NSManagedObjectModel *sModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    
    modelURL = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"Media 1.5" ofType:@"mom"]];
    NSManagedObjectModel *sMediaModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    
    SVMigrationManager *manager = [[SVMigrationManager alloc] initWithSourceModel:sModel
                                                                       mediaModel:sMediaModel
                                                                 destinationModel:[KTDocument managedObjectModel]];
    
    
    OBASSERT(manager);
    if (![manager migrateDocumentFromURL:inOriginalContentsURL
                        toDestinationURL:inURL
                                   error:outError]) return NO;
    
    
    
    // #108740
    KTDocument *document = [[KTDocument alloc] initWithContentsOfURL:inURL ofType:inType error:outError];
    if (!document) return NO;
    
    // Make each media graphic original size
    NSArray *graphics = [[document managedObjectContext] fetchAllObjectsForEntityForName:@"MediaGraphic" error:NULL];
    [graphics makeObjectsPerformSelector:@selector(makeOriginalSize)];
    
    // Constrain proportions
    for (SVMediaGraphic *aGraphic in graphics)
    {
        if ([aGraphic isConstrainProportionsEditable]) [aGraphic setConstrainsProportions:YES];
    }
    
    // Then reduce size to fit on page
    [document designDidChange];
    
    // Save
    if (![document saveToURL:inURL ofType:inType forSaveOperation:NSSaveOperation error:outError])
    {
        [document release];
        return NO;
    }
    
    [document close];
    [document release];
    
    
    return YES;
}

- (BOOL)keepBackupFile;
{
    // Only want to keep backup when migrating in case you need to get back to 1.6 land
    BOOL result = ([[self fileType] isEqualToString:kSVDocumentTypeName_1_5] ? YES : [super keepBackupFile]);
    return result;
}

@end
