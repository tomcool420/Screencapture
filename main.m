#include <dlfcn.h>
#include <stdlib.h>
#import <UIKit/UIKit.h>
#include <sys/time.h>
#include <string.h>
#import <IOSurface/IOSurface.h>
#import <Foundation/Foundation.h>
#define TILE_WIDTH 64
#define TILE_HEIGHT 16


unsigned int framebufferIndexForPoint(unsigned int x, unsigned int y,unsigned int xtiles)
{
//    unsigned int xdiv=64;
//    unsigned int ydiv = 16;
    // What row and column of the grid is our pixel in?
    unsigned int column = x / TILE_WIDTH;
    unsigned int row = y / TILE_HEIGHT;
    unsigned int cell_number = (row * xtiles) + column;
    
    // How far from the origin of the cell is our pixel?
    unsigned int grid_offset_x = x % TILE_WIDTH;
    unsigned int grid_offset_y = y % TILE_HEIGHT;
    unsigned int grid_offset = (grid_offset_y * TILE_WIDTH) + grid_offset_x;
    
    unsigned int framebuffer_index = (cell_number * 1024) + grid_offset;
    return framebuffer_index;
    
}
NSData *dataForImage(UIImage *image, NSString *path)
{
    NSData *imageData=nil;
    if ([[path pathExtension] localizedCaseInsensitiveCompare:@"png"]==NSOrderedSame) 
        imageData=UIImagePNGRepresentation(image);
    if ([[path pathExtension] localizedCaseInsensitiveCompare:@"jpg"]==NSOrderedSame ||
        [[path pathExtension] localizedCaseInsensitiveCompare:@"jpeg"]==NSOrderedSame)
        imageData=UIImageJPEGRepresentation(image,1.0);
    return imageData;
}
NSData *dataForCGImage(CGImageRef img, NSString *path)
{
    UIImage *realImage=[[UIImage alloc]initWithCGImage:img];
    NSData *d = dataForImage(realImage,path);
    [realImage release];
    return d;
}
void printSurfaceInfo(IOSurfaceRef ref)
{
    uint32_t aseed;
    IOSurfaceLock(ref, kIOSurfaceLockReadOnly, &aseed);
    uint32_t width = IOSurfaceGetWidth(ref);
    uint32_t height = IOSurfaceGetHeight(ref);
    uint32_t seed = IOSurfaceGetSeed(ref);
    uint32_t bytesPerElement = IOSurfaceGetBytesPerElement(ref);
    uint32_t bytesPerRow = IOSurfaceGetBytesPerRow(ref);
    OSType pixFormat = IOSurfaceGetPixelFormat(ref);
    uint32_t * basePtr = IOSurfaceGetBaseAddress(ref);
    size_t planeCount = IOSurfaceGetPlaneCount(ref);
    size_t eltWidth = IOSurfaceGetElementWidth(ref);
    char formatStr[5];
    int i;
    for(i=0; i<4; i++ ) {
        formatStr[i] = ((char*)&pixFormat)[3-i];
    }
    formatStr[4]=0;
    
    printf("  [?] ref=0x%08x base=0x%08x (%d x %d) seed=%d format='%s' BpE=%d, BpR=%d width=%d height=%d\n",
           ref,basePtr,width,height,seed,formatStr,bytesPerElement,bytesPerRow,width,height);
    printf("         planes: %d elementWidth: %d plane width: %d\n",planeCount,eltWidth,IOSurfaceGetWidthOfPlane(ref,0));
    IOSurfaceUnlock(ref, kIOSurfaceLockReadOnly, &aseed);
}
int saveIOSurface(NSString *path, IOSurfaceID searchId,int minWidth, int minHeight, BOOL tiles)
{
    IOSurfaceRef ref = IOSurfaceLookup(searchId);
    uint32_t aseed;
    IOSurfaceLock(ref, kIOSurfaceLockReadOnly, &aseed);
    uint32_t width = IOSurfaceGetWidth(ref);
    uint32_t height = IOSurfaceGetHeight(ref);
    uint32_t bytesPerRow = IOSurfaceGetBytesPerRow(ref);
    OSType pixFormat = IOSurfaceGetPixelFormat(ref);
    uint32_t * basePtr = IOSurfaceGetBaseAddress(ref);
    char formatStr[5];
    int i;
    for(i=0; i<4; i++ ) {
        formatStr[i] = ((char*)&pixFormat)[3-i];
    }
    formatStr[4]=0;
    printSurfaceInfo(ref);
    NSString *s = [NSString stringWithCString:formatStr encoding:NSUTF8StringEncoding];
    if (![s isEqualToString:@"BGRA"]) {
        printf("Error: Only BGRA surfaces supported for now\n");
        return 1;
    }
    if (width<minWidth) {
        printf("Error: surface width < minimum width\n");
        printf("Please Specify minimum width with -w or --width\n");
        return 2;
    }
    if (height<minHeight) {
        printf("Error: surface height < minimum height\n");
        printf("Please Specify minimum width with -h or --height\n");
        return 2;
    }
    unsigned int xtiles=width/TILE_WIDTH;
    uint32_t *ptr = calloc(width*height *4, sizeof (uint32_t));
#ifdef DEBUG
    NSDate *startTime = [NSDate date];
#endif
    uint32_t xx=0;
    uint32_t yy=0;
    int ctr=0;
    if (tiles) {
        for (yy=0; yy<height; yy++) {
            for (xx=0; xx<xtiles; xx++) {
                ctr=yy*width+xx*TILE_WIDTH;
                int ind=framebufferIndexForPoint(xx*TILE_WIDTH, yy,xtiles);
                memcpy(&ptr[ctr],&basePtr[ind],TILE_WIDTH*sizeof(uint32_t));
            }
        }
    }
#ifdef DEBUG
    NSTimeInterval rearrangeTime=-[startTime timeIntervalSinceNow];
#endif
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, (tiles?ptr:basePtr), (width * height * 4), NULL);
    CGImageRef cgImage=CGImageCreate(width, height, 8,
                                     8*4, bytesPerRow,
                                     CGColorSpaceCreateDeviceRGB(), kCGImageAlphaNoneSkipFirst |kCGBitmapByteOrder32Little,
                                     provider, NULL,
                                     YES, kCGRenderingIntentDefault);
#ifdef DEBUG
    NSTimeInterval cgImageTime=-[startTime timeIntervalSinceNow]-rearrangeTime;
#endif
    NSData *imageData=dataForCGImage(cgImage,path);
    if (imageData==nil) {
        printf("Error: Problem with conversion to NSData: exiting...\n");
        return 3;
    }
    BOOL d = [imageData writeToFile:path atomically:YES];
    if (d) {
        printf("IOSurface %d was successfully written to %s\n",searchId,[path UTF8String]);
    }
#ifdef DEBUG
    NSTimeInterval finishTime=-[startTime timeIntervalSinceNow];
    printf("times %lf %lf %lf\n",rearrangeTime,cgImageTime,finishTime);
#endif
    return 0;
}

int IOSurfaceAcceleratorSave(NSString *path, IOSurfaceID searchId,int minWidth, int minHeight, BOOL tiles)
{
    IOSurfaceRef ref = IOSurfaceLookup(searchId);
    uint32_t aseed;
    IOSurfaceLock(ref, kIOSurfaceLockReadOnly, &aseed);
    uint32_t width = IOSurfaceGetWidth(ref);
    uint32_t height = IOSurfaceGetHeight(ref);
    OSType pixFormat = IOSurfaceGetPixelFormat(ref);
    char formatStr[5];
    for(int i=0; i<4; i++ ) {
        formatStr[i] = ((char*)&pixFormat)[3-i];
    }
    NSString *s = [NSString stringWithCString:formatStr encoding:NSUTF8StringEncoding];
    if (![s isEqualToString:@"BGRA"] && ![s isEqualToString:@"ARGB"]) {
        printf("Error: Only BGRA/ARGB surfaces supported for now\n");
        return 1;
    }
    if (width<minWidth) {
        printf("Error: surface width < minimum width\n");
        printf("Please Specify minimum width with -w or --width\n");
        return 2;
    }
    if (height<minHeight) {
        printf("Error: surface height < minimum height\n");
        printf("Please Specify minimum width with -h or --height\n");
        return 2;
    }
    printSurfaceInfo(ref);
#ifdef DEBUG
    NSDate *startTime = [NSDate date];
#endif
    IOSurfaceAcceleratorRef accel=nil;
    IOSurfaceAcceleratorCreate(NULL,NULL,&accel);
    if (accel==nil) {
        printf("accelerator was not created");
        return 3;
    }
#ifdef DEBUG
    NSTimeInterval rearrangeTime=-[startTime timeIntervalSinceNow];
#endif
    int pitch = width * 4, allocSize = 4 * width * height;
    int bPE = 4;
    char pixelFormat[4] = {'A', 'R', 'G', 'B'};
     CFMutableDictionaryRef dict;
    dict = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                     &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(dict, kIOSurfaceIsGlobal, kCFBooleanTrue);
    //CFDictionarySetValue(dict, kIOSurfaceMemoryRegion, (CFStringRef)@"PurpleEDRAM");
    CFDictionarySetValue(dict, kIOSurfaceBytesPerRow,
                         CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &pitch));
    CFDictionarySetValue(dict, kIOSurfaceBytesPerElement,
                         CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &bPE));
    CFDictionarySetValue(dict, kIOSurfaceWidth,
                         CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &width));
    CFDictionarySetValue(dict, kIOSurfaceHeight,
                         CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &height));
    CFDictionarySetValue(dict, kIOSurfacePixelFormat,
                         CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, pixelFormat));
    CFDictionarySetValue(dict, kIOSurfaceAllocSize,
                         CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &allocSize));
    IOSurfaceRef surf = IOSurfaceCreate(dict);
    
    CFDictionaryRef ed = (CFDictionaryRef) [[NSDictionary dictionaryWithObjectsAndKeys:nil] retain];
#ifdef DEBUG
    NSTimeInterval createTime=-[startTime timeIntervalSinceNow];
#endif
    IOSurfaceAcceleratorTransferSurface(accel,ref,surf,ed,NULL);
#ifdef DEBUG
    NSTimeInterval convertTime=-[startTime timeIntervalSinceNow]-createTime;
#endif
    IOSurfaceUnlock(ref,kIOSurfaceLockReadOnly,&aseed);
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, IOSurfaceGetBaseAddress(surf), (width * height * 4), NULL);
    CGImageRef cgImage=CGImageCreate(width, height, 8,
                                     8*4, IOSurfaceGetBytesPerRow(surf),
                                     CGColorSpaceCreateDeviceRGB(), kCGImageAlphaNoneSkipFirst |kCGBitmapByteOrder32Little,
                                     provider, NULL,
                                     YES, kCGRenderingIntentDefault);
    NSData *imageData = dataForCGImage(cgImage,path);
    if (imageData==nil) {
        printf("Error: Problem with conversion to NSData: exiting...\n");
        return 3;
    }
    BOOL d = [imageData writeToFile:path atomically:YES];
    if (d) {
        printf("IOSurface %d was successfully written to %s\n",searchId,[path UTF8String]);
    }
#ifdef DEBUG
    NSTimeInterval finishTime=-[startTime timeIntervalSinceNow];
    printf("times %lf %lf %lf\n",createTime,convertTime,finishTime);
#endif
    return 0;
    
}
void ReportIOSurfaces(int minWidth, int minHeight, int searchNumber)
{
    for(IOSurfaceID searchId = 0 ; searchId < searchNumber; searchId++ )
    {
        IOSurfaceRef ref = IOSurfaceLookup(searchId);
        
        if (ref) 
        {
            uint32_t width = IOSurfaceGetWidth(ref);
            uint32_t height = IOSurfaceGetHeight(ref);
            OSType pixFormat = IOSurfaceGetPixelFormat(ref);
            char formatStr[5];
            int i;
            for(i=0; i<4; i++ ) {
                formatStr[i] = ((char*)&pixFormat)[3-i];
            }
            formatStr[4]=0;
            if (width > minWidth && height > minHeight/*&& seed == surfaceSeedCounter*/)
            {
                uint32_t bytesPerElement = IOSurfaceGetBytesPerElement(ref);
                uint32_t bytesPerRow = IOSurfaceGetBytesPerRow(ref);
                int rowBytesLeftover = (int)bytesPerRow - (int)width*bytesPerElement;
                printf("  [?] id=%d ref=0x%08x base=0x%08x (%d x %d) seed=%d format='%s' BpE=%d rowPad=%d planes:%d\n",
                       searchId,ref,IOSurfaceGetBaseAddress(ref),width,height,IOSurfaceGetSeed(ref),formatStr,
                       bytesPerElement,rowBytesLeftover,IOSurfaceGetPlaneCount(ref));
            }
        }
    }
}

int main(int argc, char **argv, char **envp) {
    NSAutoreleasePool *p = [[NSAutoreleasePool alloc]init];
    int i=0;
    NSString *path=@"Screenshot.png";
    IOSurfaceID surface=1;
    int minWidth=640;
    int minHeight=480;
    int searchNumber=2000;
    BOOL old = NO;
    BOOL tiles=YES;
    BOOL report=NO;
    if (argc>1) 
    {
        if ([[NSString stringWithCString:argv[1] encoding:NSUTF8StringEncoding] isEqualToString:@"--help"]) {
            printf("usage: screencapture [path] [options]\n\n");
            printf("default:\n    screencapture Screenshot.png -s 1 -w 640 -h 480 -t 1\n\n");
            printf("options:\n");
            printf("    --surface (-s) [requires one argument (unsigned int)] \n                 saves this surface to file\n");
            printf("    --width (-w)   [requires one argument (unsigned int)] \n                 minimum width for surface to be saved (default 640)\n");
            printf("    --height (-h)  [requires one argument (unsigned int)] \n                 minimum height for surface to be saved (default 480)\n");
            printf("    --tiles (-t)   [requires one argument (BOOL)] \n                 should use tile conversion (default YES (1))\n");
            printf("    --report       [no arguments]\n                 reports on all IOSurfaces (uses -w and -h to filter)\n");
            printf("    --old          [no arguments]\n                 uses old method to save convert the surface (slower)\n                 new method (default) uses IOSurfaceAccelerator");
            printf("    --help         [requires no arguments ] \n                 this help");

            
            printf("\n");
            return 0;
        }
        for(i=1;i<argc;i++)
        {
            NSString *option = [NSString stringWithCString:argv[i] encoding:NSUTF8StringEncoding];
            if ([[option pathExtension] localizedCaseInsensitiveCompare:@"png"]==NSOrderedSame||
                [[option pathExtension] localizedCaseInsensitiveCompare:@"jpg"]==NSOrderedSame||
                [[option pathExtension] localizedCaseInsensitiveCompare:@"jpeg"]==NSOrderedSame) {
                path=option;
            }
            if ([option hasPrefix:@"-"]) {
                if ([option isEqualToString:@"-s"]||
                    [option isEqualToString:@"--surface"])
                {
                    if (argc>(i+1)) 
                    {
                        surface=[[NSString stringWithCString:argv[i+1] encoding:NSUTF8StringEncoding] intValue];
                    }
                    else 
                    {
                        printf("%s requires a value (integer)\n",argv[i]);
                        return 10;
                    }
                }
                if ([option isEqualToString:@"--report"])
                {
                    report=YES;
                }
                if ([option isEqualToString:@"--old"])
                {
                    old=YES;
                }
                if ([option isEqualToString:@"-w"]||
                    [option isEqualToString:@"--width"]) {
                    if (argc>(i+1)) {
                        minWidth=[[NSString stringWithCString:argv[i+1] encoding:NSUTF8StringEncoding] intValue];
                    }
                    else {
                        printf("%s requires a value (integer)\n",argv[i]);
                        return 10;
                    }

                }
                if ([option isEqualToString:@"-h"]||
                    [option isEqualToString:@"--height"]) {
                    if (argc>(i+1)) {
                        minHeight=[[NSString stringWithCString:argv[i+1] encoding:NSUTF8StringEncoding] intValue];
                    }
                    else {
                        printf("%s requires a value (integer)\n",argv[i]);
                        return 10;
                    }

                }
                if ([option isEqualToString:@"-t"]||
                    [option isEqualToString:@"--tiles"]) {
                    if (argc>(i+1)) {
                        tiles=[[NSString stringWithCString:argv[i+1] encoding:NSUTF8StringEncoding] boolValue];
                    }
                    else {
                        printf("%s requires a value (integer)\n",argv[i]);
                        return 10;
                    }
                    
                }
                
            }
        }
    }
    
    int rvalue =0;
    if (report) {
        ReportIOSurfaces(minWidth,minHeight,searchNumber);
    }
    else
    {
        if (old) 
            rvalue=saveIOSurface(path,surface,minWidth,minHeight,tiles);
        else
            rvalue=IOSurfaceAcceleratorSave(path,surface,minWidth,minHeight,tiles);
    }
        
    [p release];
	return rvalue;
}

// vim:ft=objc
