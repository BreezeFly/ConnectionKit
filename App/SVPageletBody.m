// 
//  SVPageletBody.m
//  Sandvox
//
//  Created by Mike on 18/11/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "SVPageletBody.h"

#import "SVPagelet.h"
#import "SVBodyElement.h"

#import "NSArray+Karelia.h"
#import "NSError+Karelia.h"


@interface SVPageletBody (CoreDataGeneratedAccessors)
- (void)addElementsObject:(SVBodyElement *)value;
- (void)removeElementsObject:(SVBodyElement *)value;
- (void)addElements:(NSSet *)value;
- (void)removeElements:(NSSet *)value;
@end


#pragma mark -


@implementation SVPageletBody 

@dynamic pagelet;

#pragma mark Elements

+ (NSArray *)orderedElementsWithElements:(NSSet *)elements
{
    NSArray *result = nil;
    
    if (elements)
    {
        SVBodyElement *startElement = [elements anyObject];
        if (startElement)
        {
            result = [NSArray arrayWithDoublyLinkedListObject:startElement
                                           nextObjectSelector:@selector(nextElement)
                                       previousObjectSelector:@selector(previousElement)];
        }
        else
        {
            result = [NSArray array];
        }
    }
    
    return result;
}

@dynamic elements;
- (BOOL)validateElements:(NSSet **)elements error:(NSError **)error
{
    //  The set is only valid if it matches up to the ordered version. i.e. want to make sure nothing in the set is orphaned from the link list.
    BOOL result = YES;
    
    NSUInteger expectedCount = [[[self class] orderedElementsWithElements:*elements] count];
    if ([*elements count] > expectedCount)
    {
        result = NO;
        
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                                code:NSValidationRelationshipExceedsMaximumCountError
                                localizedDescription:@"There are more objects in elements than expected, suggesting some elements have been removed from the linked list, but not the relationship."];
    }
    else if ([*elements count] < expectedCount)
    {
        result = NO;
        
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                                code:NSValidationRelationshipLacksMinimumCountError
                                localizedDescription:@"There are fewer objects in elements than expected, suggesting some elements have been inserted into the linked list, but not the relationship."];
    }
    
    return result;
}

- (NSArray *)orderedElements;
{
    NSArray *result = [[self class] orderedElementsWithElements:[self elements]];
    return result;
}

- (SVBodyElement *)firstElement;
{
    // Start with a random element and search backwards to the beginning
    SVBodyElement *result = [[self elements] anyObject];
    
    SVBodyElement *previousElement;
    while (previousElement = [result previousElement])
    {
        result = previousElement;
    }
    
    return result;
}

- (void)addElement:(SVBodyElement *)element;
{
    // TODO: Ensure the element is not already part of another group
    [self addElementsObject:element];
}

#pragma mark HTML

- (NSString *)HTMLString;
{
    //  Piece together each of our elements to generate the HTML
    NSMutableString *result = [NSMutableString string];
    
    SVBodyElement *startElement = [[self elements] anyObject];
    if (startElement)
    {
        [result appendString:[startElement HTMLString]];
        
        // Add on everything after the start element
        SVBodyElement *anElement = startElement;
        while (anElement = [anElement nextElement])
        {
            [result appendString:[anElement HTMLString]];
        }
        
        // Insert everything before the start element
        anElement = startElement;
        while (anElement = [anElement previousElement])
        {
            [result insertString:[anElement HTMLString] atIndex:0];
        }
    }
    
    
    return result;
}

- (void)updateWithHTMLElement:(DOMHTMLElement *)element;
{
    
}

@end
