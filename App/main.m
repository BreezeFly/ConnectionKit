//
//  main.m
//  Sandvox
//
//  Copyright 2004-2011 Karelia Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <Foundation/NSDebug.h>
#import <Carbon/Carbon.h>
#include <stdlib.h>
#import <sys/types.h>
#import <sys/time.h>
#import <sys/resource.h>
#include <stdio.h>
#include <errno.h>
#include "Debug.h"

#import "Registration.h"

#import <sys/stat.h>
#import <openssl/bio.h>
#import <openssl/pkcs7.h>
#import <openssl/x509.h>
#import <Security/SecKeychainItem.h>
#import <Security/CodeSigning.h>
#import <objc/runtime.h>
#import "Payload.h"
#import "ethernet.h"



// MAS validation based on: https://github.com/AlanQuatermain/mac-app-store-validation-sample.git


static inline SecCertificateRef AppleRootCA( void )
{
    SecKeychainRef roots = NULL;
    SecKeychainSearchRef search = NULL;
    SecCertificateRef cert = NULL;
    BOOL cfReleaseKeychain = YES;
    
    // there's a GC bug with this guy it seems
    OSStatus err = SecKeychainOpen( "/System/Library/Keychains/SystemRootCertificates.keychain", &roots );
    if ( [NSGarbageCollector defaultCollector] != nil )
    {
        CFMakeCollectable(roots);
        cfReleaseKeychain = NO;
    }
    
    if ( err != noErr )
    {
        CFStringRef errStr = SecCopyErrorMessageString( err, NULL );
        NSLog( @"Error: %ld (%@)", err, errStr );
        CFRelease( errStr );
        return NULL;
    }
    
    SecKeychainAttribute labelAttr = { .tag = kSecLabelItemAttr, .length = 13, .data = (void *)"Apple Root CA" };
    SecKeychainAttributeList attrs = { .count = 1, .attr = &labelAttr };
    
    err = SecKeychainSearchCreateFromAttributes( roots, kSecCertificateItemClass, &attrs, &search );
    if ( err != noErr )
    {
        CFStringRef errStr = SecCopyErrorMessageString( err, NULL );
        NSLog( @"Error: %ld (%@)", err, errStr );
        CFRelease( errStr );
        if ( cfReleaseKeychain )
            CFRelease( roots );
        return NULL;
    }
    
    SecKeychainItemRef item = NULL;
    err = SecKeychainSearchCopyNext( search, &item );
    if ( err != noErr )
    {
        CFStringRef errStr = SecCopyErrorMessageString( err, NULL );
        NSLog( @"Error: %ld (%@)", err, errStr );
        CFRelease( errStr );
        if ( cfReleaseKeychain )
            CFRelease( roots );
        
        return NULL;
    }
    
    cert = (SecCertificateRef)item;
    CFRelease( search );
    
    if ( cfReleaseKeychain )
        CFRelease( roots );
    
    return ( cert );
}


static NSString* hardcoded_identifier = @"com.karelia.Sandvox";
static NSString* hardcoded_version = APP_STORE_VERSION;


typedef int (*startup_call_t)(int, const char **);


static inline int verifySignature( int argc, startup_call_t *theCall, id * receiptPath )
{
    // the pkcs7 container (the receipt) and the output of the verification
    PKCS7 *p7 = NULL;
    
    // The Apple Root CA in its OpenSSL representation.
    X509 *Apple = NULL;
    
    // The root certificate for chain-of-trust verification
    X509_STORE *store = X509_STORE_new();
    
    // initialize both BIO variables using BIO_new_mem_buf() with a buffer and its size...
    //b_p7 = BIO_new_mem_buf((void *)[receiptData bytes], [receiptData length]);
    FILE *fp = fopen( [*receiptPath fileSystemRepresentation], "rb" );
    
    if ( fp == NULL )
    {
        NSLog( @"No receipt found" );
        *theCall = (startup_call_t)&exit;
        return ( 173 );
    }
    
    // initialize b_out as an out
    BIO *b_out = BIO_new(BIO_s_mem());
    
    // capture the content of the receipt file and populate the p7 variable with the PKCS #7 container
    p7 = d2i_PKCS7_fp( fp, NULL );
    fclose( fp );
    
    // get the Apple root CA from http://www.apple.com/certificateauthority and load it into b_X509
    //NSData * root = [NSData dataWithContentsOfURL: [NSURL URLWithString: @"http://www.apple.com/certificateauthority/AppleComputerRootCertificate.cer"]];
    SecCertificateRef cert = AppleRootCA();
    if ( cert == NULL )
    {
        NSLog( @"Failed to load Apple Root CA" );
        *theCall = (startup_call_t)&exit;
        return ( 173 );
    }
    
    CFDataRef data = SecCertificateCopyData( cert );
    CFRelease( cert );
    
    //b_x509 = BIO_new_mem_buf( (void *)CFDataGetBytePtr(data), (int)CFDataGetLength(data) );
    const unsigned char * pData = CFDataGetBytePtr(data);
    Apple = d2i_X509( NULL, &pData, (long)CFDataGetLength(data) );
    X509_STORE_add_cert( store, Apple );
    
    // verify the signature. If the verification is correct, b_out will contain the PKCS #7 payload and rc will be 1.
    int rc = PKCS7_verify( p7, NULL, store, NULL, b_out, 0 );
    
    // could also verify the fingerprints of the issue certificates in the receipt
    
    unsigned char *pPayload = NULL;
    size_t len = BIO_get_mem_data(b_out, &pPayload);
    *receiptPath = [NSData dataWithBytes: pPayload length: len];
    
    // clean up
    //BIO_free(b_p7);
    //BIO_free(b_x509);
    BIO_free(b_out);
    PKCS7_free(p7);
    X509_free(Apple);
    X509_STORE_free(store);
    CFRelease(data);
    
    if ( rc != 1 )
    {
        *theCall = (startup_call_t)&exit;
        return ( 173 );
    }
    
    return ( argc );
}

static inline int examinePayload( int argc, startup_call_t *theCall, id * dataPtr )
{
    NSData * payloadData = (NSData *)(*dataPtr);
    void * data = (void *)[payloadData bytes];
    size_t len = (size_t)[payloadData length];
    
    Payload_t * payload = NULL;
    asn_dec_rval_t rval;
    
    // parse the buffer using the asn1c-generated decoder.
    do
    {
        rval = asn_DEF_Payload.ber_decoder( NULL, &asn_DEF_Payload, (void **)&payload, data, len, 0 );
        
    } while ( rval.code == RC_WMORE );
    
    if ( rval.code == RC_FAIL )
    {
        *theCall = (startup_call_t)&exit;
        return ( 173 );
    }
    
    OCTET_STRING_t *bundle_id = NULL;
    OCTET_STRING_t *bundle_version = NULL;
    OCTET_STRING_t *opaque = NULL;
    OCTET_STRING_t *hash = NULL;
    
    // iterate over the attributes, saving the values required for the hash
    size_t i;
    for ( i = 0; i < payload->list.count; i++ )
    {
        ReceiptAttribute_t *entry = payload->list.array[i];
        switch ( entry->type )
        {
            case 2:
                bundle_id = &entry->value;
                break;
            case 3:
                bundle_version = &entry->value;
                break;
            case 4:
                opaque = &entry->value;
                break;
            case 5:
                hash = &entry->value;
                break;
            default:
                break;
        }
    }
    
    if ( bundle_id == NULL || bundle_version == NULL || opaque == NULL || hash == NULL )
    {
        free( payload );
        *theCall = (startup_call_t)&exit;
        return ( 173 );
    }
    
    NSString * bidStr = [[[NSString alloc] initWithBytes: (bundle_id->buf + 2) length: (bundle_id->size - 2) encoding: NSUTF8StringEncoding] autorelease];
    if ( [bidStr isEqualToString: hardcoded_identifier] == NO )
    {
        free( payload );
        *theCall = (startup_call_t)&exit;
        return ( 173 );
    }
    
    NSString * dvStr = [[[NSString alloc] initWithBytes: (bundle_version->buf + 2) length: (bundle_version->size - 2) encoding: NSUTF8StringEncoding] autorelease];
    if ( [dvStr isEqualToString: hardcoded_version] == NO )
    {
        free( payload );
        *theCall = (startup_call_t)&exit;
        return ( 173 );
    }
    
    CFDataRef macAddress = CopyMACAddressData();
    if ( macAddress == NULL )
    {
        free( payload );
        *theCall = (startup_call_t)&exit;
        return ( 173 );
    }
    
    UInt8 *guid = (UInt8 *)CFDataGetBytePtr( macAddress );
    size_t guid_sz = CFDataGetLength( macAddress );
    
    // initialize an EVP context for OpenSSL
    EVP_MD_CTX evp_ctx;
    EVP_MD_CTX_init( &evp_ctx );
    
    UInt8 digest[20];
    
    // set up EVP context to compute an SHA-1 digest
    EVP_DigestInit_ex( &evp_ctx, EVP_sha1(), NULL );
    
    // concatenate the pieces to be hashed. They must be concatenated in this order.
    EVP_DigestUpdate( &evp_ctx, guid, guid_sz );
    EVP_DigestUpdate( &evp_ctx, opaque->buf, opaque->size );
    EVP_DigestUpdate( &evp_ctx, bundle_id->buf, bundle_id->size );
    
    // compute the hash, saving the result into the digest variable
    EVP_DigestFinal_ex( &evp_ctx, digest, NULL );
    
    // clean up memory
    EVP_MD_CTX_cleanup( &evp_ctx );
    
    // compare the hash
    int match = sizeof(digest) - hash->size;
    match |= memcmp( digest, hash->buf, MIN(sizeof(digest), hash->size) );
    
    free( payload );
    if ( match != 0 )
    {
        *theCall = (startup_call_t)&exit;
        return ( 173 );
    }
    
    return ( argc );
}

static inline int locateReceipt(int argc, startup_call_t *theCall, id * pathPtr)
{
    // 10.7
    if ( [[NSBundle mainBundle] respondsToSelector:@selector(appStoreReceiptURL)] )
    {
        NSURL *receiptURL = [[NSBundle mainBundle] performSelector:@selector(appStoreReceiptURL)];
        *pathPtr = [receiptURL path];
    }
    // 10.6
    if ( *pathPtr == nil )
    {
        *pathPtr = [[[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent: @"Contents/_MASReceipt/receipt"] stringByStandardizingPath];
    }
    struct stat statBuf;
    if ( stat([*pathPtr fileSystemRepresentation], &statBuf) != 0 )
    {
        LOG((@"no receipt found in .app, we really shouldn't even continue"));
        *theCall = (startup_call_t)&exit;
        return ( 173 );
    }
    
    ERR_load_PKCS7_strings();
    ERR_load_X509_strings();
    OpenSSL_add_all_digests();
    
    return ( argc );
}


int verifyKareliaProduct( int argc, startup_call_t *theCall, id * obj_arg )
{
    SecStaticCodeRef staticCode = NULL;
    if ( SecStaticCodeCreateWithPath((CFURLRef)[[NSBundle mainBundle] bundleURL], kSecCSDefaultFlags, &staticCode) != noErr )
    {
        *theCall = (startup_call_t)&exit;
        return ( 173 );
    }
    
    // the last parameter here could/should be a compiled requirement stating that the code
    // must be signed by YOUR certificate and no-one else's.
    if ( SecStaticCodeCheckValidity(staticCode, kSecCSCheckAllArchitectures, NULL) != noErr )
    {
        *theCall = (startup_call_t)&exit;
        return ( 173 );
    }
    
    return ( argc );
}

int main(int argc, char *argv[])
{	    
	LOG((@"required = %d, allowed = %d", MAC_OS_X_VERSION_MIN_REQUIRED, MAC_OS_X_VERSION_MAX_ALLOWED));
    
    ///////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////
    
#ifdef MAC_APP_STORE
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    if ( [hardcoded_identifier isEqualToString:[[NSBundle mainBundle] bundleIdentifier]] == NO )
    {
        LOG((@"hardcoded CFBundleIdentifier does not match Info.plist!"));
	}	
	if ( [hardcoded_version isEqualToString:[[[NSBundle mainBundle] infoDictionary] objectForKey: @"CFBundleIdentifier"]] == NO )
    {
        LOG((@"hardcoded CFBundleShortVersionString does not match Info.plist!"));
	}	
	
    startup_call_t theCall = &NSApplicationMain;
    id obj_arg = nil;
    argc = locateReceipt(argc, &theCall, &obj_arg);
    if ( argc != 173 ) 
    {
        argc = verifySignature(argc, &theCall, &obj_arg);
    }
    if ( argc != 173 )
    {
        argc = examinePayload(argc, &theCall, &obj_arg);
    }
    if ( argc != 173 )
    {
        argc = verifyKareliaProduct(argc, &theCall, &obj_arg);
    }
    
    [pool drain];
    
    // if this is the exit() function, it shouldn't ever return
    int rc = theCall(argc, (const char **) argv);
    if ( argc > 50 )
        return ( argc );
    
    return ( rc );
    
#else
    
    return NSApplicationMain(argc, (const char **) argv);
#endif
}
