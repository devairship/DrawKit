/**
 @author Contributions from the community; see CONTRIBUTORS.md
 @date 2005-2016
 @copyright MPL2; see LICENSE.txt
*/

#import "DKGradient.h"

#import "DKDrawKitMacros.h"
#import "DKGradientExtensions.h"
#import "LogEvent.h"
#import "NSColor+DKAdditions.h"

#ifndef __STANDALONE__
#import "DKDrawableObject+Metadata.h"
#include <tgmath.h>
#endif

#pragma mark Contants(Non - localized)
NSString* const kDKNotificationGradientWillAddColorStop = @"kDKNotificationGradientWillAddColorStop";
NSString* const kDKNotificationGradientDidAddColorStop = @"kDKNotificationGradientDidAddColorStop";
NSString* const kDKNotificationGradientWillRemoveColorStop = @"kDKNotificationGradientWillRemoveColorStop";
NSString* const kDKNotificationGradientDidRemoveColorStop = @"kDKNotificationGradientDidRemoveColorStop";
NSString* const kDKNotificationGradientWillChange = @"kDKNotificationGradientWillChange";
NSString* const kDKNotificationGradientDidChange = @"kDKNotificationGradientDidChange";

#pragma mark Static Vars

#pragma mark Function Declarations
static inline double powerMap(double x, double y);
static inline double sineMap(double x, double y);
static inline void transformHSV_RGB(CGFloat* components);
static inline void transformRGB_HSV(CGFloat* components);
static inline void resolveHSV(CGFloat* color1, CGFloat* color2);

#pragma mark -
@interface DKColorStop ()

@property (weak) DKGradient* owner;

@end

#pragma mark -
@implementation DKGradient
#pragma mark As a DKGradient

#pragma mark - simple gradient convenience methods

+ (DKGradient*)defaultGradient
{
	DKGradient* grad = [[DKGradient alloc] init];

	[grad addColor:[NSColor rgbBlack]
				at:0.0];
	[grad addColor:[NSColor rgbWhite]
				at:1.0];

	return grad;
}

+ (DKGradient*)gradientWithStartingColor:(NSColor*)c1 endingColor:(NSColor*)c2
{
	return [self gradientWithStartingColor:c1
							   endingColor:c2
									  type:kDKGradientTypeLinear
									 angle:0.0];
}

+ (DKGradient*)gradientWithStartingColor:(NSColor*)c1 endingColor:(NSColor*)c2 type:(DKGradientType)gt angle:(CGFloat)degrees
{
	DKGradient* grad = [[DKGradient alloc] init];

	[grad addColor:c1
				at:0.0];
	[grad addColor:c2
				at:1.0];
	[grad setGradientType:gt];
	[grad setAngleInDegrees:degrees];

	return grad;
}

#pragma mark -
#pragma mark - modified copies

- (DKGradient*)gradientByColorizingWithColor:(NSColor*)color
{
	DKGradient* copy = [self copy];

	NSColor* rgb = [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace];

	for (DKColorStop* stop in copy.colorStops) {
		stop.color = [stop.color colorWithHueAndSaturationFrom:rgb];
	}

	return copy;
}

- (DKGradient*)gradientWithAlpha:(CGFloat)alpha
{
	DKGradient* copy = [self copy];

	for (DKColorStop* stop in copy.colorStops) {
		[stop setAlpha:alpha];
	}

	return copy;
}

#pragma mark -
#pragma mark - setting up the Color stops

- (DKColorStop*)addColor:(NSColor*)Color at:(CGFloat)pos
{
	DKColorStop* stop = [[DKColorStop alloc] initWithColor:Color
														at:pos];
	[self addColorStop:stop];
	return stop;
}

- (void)addColorStop:(DKColorStop*)stop
{
	if (![[self colorStops] containsObject:stop]) {
		[[NSNotificationCenter defaultCenter] postNotificationName:kDKNotificationGradientWillAddColorStop
															object:self];
		[self insertObject:stop
			inColorStopsAtIndex:[m_colorStops count]];
		[stop setOwner:self];
		[self sortColorStops];
		[[NSNotificationCenter defaultCenter] postNotificationName:kDKNotificationGradientDidAddColorStop
															object:self];
	}
}

- (void)removeLastColor
{
	[self removeColorStop:[m_colorStops lastObject]];
}

- (void)removeColorStop:(DKColorStop*)stop
{
	if ([[self colorStops] containsObject:stop]) {
		[[NSNotificationCenter defaultCenter] postNotificationName:kDKNotificationGradientWillRemoveColorStop
															object:self];
		NSUInteger indx = [m_colorStops indexOfObject:stop];
		[self removeObjectFromColorStopsAtIndex:indx];

		[[NSNotificationCenter defaultCenter] postNotificationName:kDKNotificationGradientDidRemoveColorStop
															object:self];
	}
}

- (void)removeAllColors
{
	[[NSNotificationCenter defaultCenter] postNotificationName:kDKNotificationGradientWillRemoveColorStop
														object:self];
	[m_colorStops removeAllObjects];
	[[NSNotificationCenter defaultCenter] postNotificationName:kDKNotificationGradientDidRemoveColorStop
														object:self];
}

/** @brief Sets the list of Color stops in the gradient

 A gradient needs a minimum of two Colors to be a gradient, but will function with one.
 @param stops an array of DKColorStop objects
 */
- (void)setColorStops:(NSArray*)stops
{
	//	LogEvent_(kStateEvent, @"setting colour stops, new = %@", stops );

	[[NSNotificationCenter defaultCenter] postNotificationName:kDKNotificationGradientWillAddColorStop
														object:self];
	m_colorStops = [stops mutableCopy];

	// set the owner ref - no longer needed for unarchiving gradients - compat with older files

	[m_colorStops makeObjectsPerformSelector:@selector(setOwner:)
								  withObject:self];

	[[NSNotificationCenter defaultCenter] postNotificationName:kDKNotificationGradientDidAddColorStop
														object:self];
}

/** @brief Returns the list of Color stops in the gradient

 A gradient needs a minimum of two Colors to be a gradient, but will function with one.
 @return the array of DKColorStop (color + position) objects in the gradient
 */
- (NSArray*)colorStops
{
	return [m_colorStops copy];
}

- (void)sortColorStops
{
	[m_colorStops sortWithOptions:NSSortStable
				  usingComparator:^NSComparisonResult(DKColorStop* lh, DKColorStop* rh) {
					  CGFloat lp = [lh position];
					  CGFloat rp = [rh position];

					  //NSLog(@"positions: %f, %f", lp, rp );

					  if (lp < rp)
						  return NSOrderedAscending;
					  else if (lp > rp)
						  return NSOrderedDescending;
					  else
						  return NSOrderedSame;
				  }];
}

- (void)reverseColorStops
{
	[[NSNotificationCenter defaultCenter] postNotificationName:kDKNotificationGradientWillChange
														object:self];
	for (DKColorStop* stop in self.colorStops) {
		stop.position = 1.0 - stop.position;
	}

	[self sortColorStops];
	[[NSNotificationCenter defaultCenter] postNotificationName:kDKNotificationGradientDidChange
														object:self];
}

#pragma mark -
#pragma mark - KVO compliant accessors

- (NSUInteger)countOfColorStops
{
	return [m_colorStops count];
}

- (DKColorStop*)objectInColorStopsAtIndex:(NSUInteger)ix
{
	return [m_colorStops objectAtIndex:ix];
}

- (void)insertObject:(DKColorStop*)stop inColorStopsAtIndex:(NSUInteger)ix
{
	if (ix >= [m_colorStops count])
		[m_colorStops addObject:stop];
	else
		[m_colorStops insertObject:stop
						   atIndex:ix];
}

- (void)removeObjectFromColorStopsAtIndex:(NSUInteger)ix
{
	[m_colorStops removeObjectAtIndex:ix];
}

#pragma mark -
#pragma mark - a variety of ways to fill a path

- (void)fillRect:(NSRect)rect
{
	[self fillPath:[NSBezierPath bezierPathWithRect:rect]];
}

- (void)fillPath:(NSBezierPath*)path
{
	NSPoint cp;

	cp.x = NSMidX([path bounds]);
	cp.y = NSMidY([path bounds]);

	[self fillPath:path
		centreOffset:NSZeroPoint];
}

- (void)fillPath:(NSBezierPath*)path centreOffset:(NSPoint)co
{
	NSRect pb = [path bounds];

	// calculate endpoints to take into account the set angle

	NSPoint sp, ep;
	CGFloat sr = 0.0;
	CGFloat er = 0.0;
	CGFloat r1, r2;

	ep.x = NSMidX(pb);
	ep.y = NSMidY(pb);

	//radius = hypot( pb.size.width, pb.size.height ) / 3.0;
	r1 = pb.size.width / 2.0;
	r2 = pb.size.height / 2.0;

	if ([self gradientType] == kDKGradientTypeLinear) {
		sp.x = ep.x - r1 * cos([self angle]);
		sp.y = ep.y - r2 * sin([self angle]);
		ep.x = ep.x + r1 * cos([self angle]);
		ep.y = ep.y + r2 * sin([self angle]);
	} else if ([self gradientType] == kDKGradientTypeRadial && m_extensionData != nil) {
		// can try to get these points from extensions data

		sp = [self mapPoint:[self radialStartingPoint]
					 toRect:pb];
		ep = [self mapPoint:[self radialEndingPoint]
					 toRect:pb];
		sr = pb.size.width * [self radialStartingRadius];
		er = pb.size.width * [self radialEndingRadius];
	} else {
		sp.x = ep.x + co.x;
		sp.y = ep.y + co.y;
		sr = 0.0;
		er = hypot(pb.size.width, pb.size.height) / 3.0;
	}

	[self fillPath:path
		startingAtPoint:sp
			startRadius:sr
		  endingAtPoint:ep
			  endRadius:er];
}

/** if \c ra is <code>NO</code>, this is optimised on the basis that it will be called from a loop with \c val going from 0 -> 1. In
 that case sequential access to the stops can be assumed and so no lookup loop is required. For random access, where
 \c val can be any value in or out of sequence, the lookup loop is required. If in doubt, pass YES.
 */
- (void)private_colorAtValue:(CGFloat)val components:(CGFloat*)components randomAccess:(BOOL)ra
{
	// if <ra> is NO, this is optimised on the basis that it will be called from a loop with <val> going from 0 -> 1. In
	// that case sequential access to the stops can be assumed and so no lookup loop is required. For random access, where
	// <val> can be any value in or out of sequence, the lookup loop is required. If in doubt, pass YES.

	NSInteger keys, k2;
	static DKColorStop* key1 = nil;
	static DKColorStop* key2 = nil;
	static NSColor* kk1;
	static NSColor* kk2;
	static CGFloat k1pos, k2pos;
	static NSInteger indx = 0;

	keys = CFArrayGetCount((CFArrayRef)m_colorStops);

	if (keys < 2)
		return;

	if (ra) {
		// random access - need to find the right stop pair to use

		key1 = [[self colorStops] objectAtIndex:0];
		key2 = [[self colorStops] objectAtIndex:1];
		k2 = 1;

		while (k2 < (keys - 1) && [key2 position] < val) {
			key1 = key2;
			key2 = [[self colorStops] objectAtIndex:++k2];
		}

		kk1 = [key1 color];
		kk2 = [key2 color];
		k1pos = [key1 position];
		k2pos = [key2 position];
	} else {
		// sequential access - can assume that the previous value of <val> already set up the right pair, so we just need
		// to see if it's crossed to the next stop position

		// first check we have intialised the starting stops:

		if (key1 == nil || val <= 0.0) {
			key1 = (DKColorStop*)CFArrayGetValueAtIndex((CFArrayRef)m_colorStops, 0); // [_colorStops objectAtIndex:0];
			key2 = (DKColorStop*)CFArrayGetValueAtIndex((CFArrayRef)m_colorStops, 1); // [_colorStops objectAtIndex:1];
			kk1 = [key1 color];
			kk2 = [key2 color];
			k1pos = [key1 position];
			k2pos = [key2 position];
			indx = 2;
		}

		// need to get next pair?

		if (val > k2pos && indx < keys) {
			key1 = key2;
			kk1 = kk2;
			k1pos = k2pos;
			key2 = (DKColorStop*)CFArrayGetValueAtIndex((CFArrayRef)m_colorStops, indx++); //[[self colorStops] objectAtIndex:index++];
			kk2 = [key2 color];
			k2pos = [key2 position];
		}
	}

	if (val <= k1pos) {
		[kk1 getRed:&components[0]
			  green:&components[1]
			   blue:&components[2]
			  alpha:&components[3]];
	} else if (val >= k2pos) {
		[kk2 getRed:&components[0]
			  green:&components[1]
			   blue:&components[2]
			  alpha:&components[3]];

		if (!ra && val >= 1.0) {
			// reached the end - reset for next sequential run

			key1 = key2 = nil;
		}
	} else {
		CGFloat p = (val - k1pos) / (k2pos - k1pos);

		switch (m_interp) {
		default:
		case DKGradientInterpolationLinear:
			break;

		case DKGradientInterpolationQuadratic:
			p = powerMap(p, 2);
			break;

		case DKGradientInterpolationCubic:
			p = powerMap(p, 3);
			break;

		case DKGradientInterpolationSinus:
			p = sineMap(p, 1);
			break;

		case DKGradientInterpolationSinus2:
			p = sineMap(p, 2);
			break;
		}

		if (m_blending == DKGradientBlendingRGB) {
			// access the stop's precached components directly for best speed:

			CGFloat* ca;
			CGFloat* cb;

			ca = key1->components;
			cb = key2->components;

			components[0] = (cb[0] - ca[0]) * p + ca[0];
			components[1] = (cb[1] - ca[1]) * p + ca[1];
			components[2] = (cb[2] - ca[2]) * p + ca[2];
			components[3] = (cb[3] - ca[3]) * p + ca[3];
		} else if (m_blending == DKGradientBlendingHSB) {
			// blend in HSV space - this method almost entirely lifted from Chad Weider (thanks!)

			CGFloat ca[4];
			CGFloat cb[4];
			[kk1 getRed:&ca[0]
				  green:&ca[1]
				   blue:&ca[2]
				  alpha:&ca[3]];
			[kk2 getRed:&cb[0]
				  green:&cb[1]
				   blue:&cb[2]
				  alpha:&cb[3]];

			transformRGB_HSV(ca);
			transformRGB_HSV(cb);
			resolveHSV(ca, cb);

			if (ca[0] > cb[0]) //if color1's hue is higher than color2's hue then
				cb[0] += 360; //	we need to move c2 one revolution around the wheel

			components[0] = (cb[0] - ca[0]) * p + ca[0];
			components[1] = (cb[1] - ca[1]) * p + ca[1];
			components[2] = (cb[2] - ca[2]) * p + ca[2];
			components[3] = (cb[3] - ca[3]) * p + ca[3];

			transformHSV_RGB(components);
		} else if (m_blending == DKGradientBlendingAlpha) {
			CGFloat* ca;
			CGFloat* cb;

			ca = key1->components;
			cb = key2->components;

			components[3] = (cb[3] - ca[3]) * p + ca[3];
		}
	}
}

#define qLogPerformanceMetrics 0

- (void)fillPath:(NSBezierPath*)path startingAtPoint:(NSPoint)sp startRadius:(CGFloat)sr endingAtPoint:(NSPoint)ep endRadius:(CGFloat)er
{
	if ([path isEmpty] || [path bounds].size.width <= 0.0 || [path bounds].size.height <= 0.0)
		return;

#if qLogPerformanceMetrics
	static NSTimeInterval total = 0;
	static NSInteger count = 0;

	NSTimeInterval average;
	NSTimeInterval startTime;

	startTime = [NSDate timeIntervalSinceReferenceDate];
	++count;
#endif

	SAVE_GRAPHICS_CONTEXT //[NSGraphicsContext saveGraphicsState];
		[path addClip];

	[self fillStartingAtPoint:sp
				  startRadius:sr
				endingAtPoint:ep
					endRadius:er];
	RESTORE_GRAPHICS_CONTEXT //[NSGraphicsContext restoreGraphicsState];

#if qLogPerformanceMetrics
		NSTimeInterval elapsed
		= [NSDate timeIntervalSinceReferenceDate] - startTime;
	total += elapsed;
	average = total / count;

	LogEvent_(kInfoEvent, @"metrics: elapsed = %f, average = %f, count = %d", elapsed, average, count);
#endif
}

#pragma mark -

/** @brief Returns the Color space used when rendering gradients

 Normally this isn't of much interest to application programmers, but if you wanted to customise
 the Colorspace used for rendering gradients, you could override this.
 @return Colorspace used for gradients
 */
+ (CGColorSpaceRef)sharedGradientColorSpace
{
	static CGColorSpaceRef sGradientColorSpace = nil;

	if (sGradientColorSpace == nil)
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_4
		sGradientColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
#else
		sGradientColorSpace = CGColorSpaceCreateDeviceRGB();
#endif

	return sGradientColorSpace;
}

- (NSGradient*)newNSGradient
{
	NSMutableArray* colArr = [[NSMutableArray alloc] initWithCapacity:m_colorStops.count];
	CGFloat* stopsArr = calloc(m_colorStops.count, sizeof(CGFloat));
	NSInteger i = 0;
	for (DKColorStop* stop in m_colorStops) {
		[colArr addObject:stop.color];
		stopsArr[i++] = stop.position;
	}

	NSGradient* grad = [[NSGradient alloc] initWithColors:colArr atLocations:stopsArr colorSpace:[NSColorSpace genericRGBColorSpace]];
	free(stopsArr);

	return grad;
}

#pragma mark -

- (void)fillStartingAtPoint:(NSPoint)sp
				startRadius:(CGFloat)sr
			  endingAtPoint:(NSPoint)ep
				  endRadius:(CGFloat)er
{
	NSGradient* gradient = [self newNSGradient];

	switch (self.gradientType) {
	case kDKGradientTypeLinear:
		[gradient drawFromPoint:sp toPoint:ep options:NSGradientDrawsBeforeStartingLocation | NSGradientDrawsAfterEndingLocation];
		break;

	case kDKGradientTypeRadial:
		[gradient drawFromCenter:sp radius:sr toCenter:ep radius:er options:NSGradientDrawsBeforeStartingLocation | NSGradientDrawsAfterEndingLocation];
		break;

	default:
		break;
	}
}

#pragma mark -
- (void)fillContext:(CGContextRef)context startingAtPoint:(NSPoint)sp
		startRadius:(CGFloat)sr
	  endingAtPoint:(NSPoint)ep
		  endRadius:(CGFloat)er
{
	[NSGraphicsContext saveGraphicsState];
	if (@available(macOS 10.10, *)) {
		NSGraphicsContext* ctx = [NSGraphicsContext graphicsContextWithCGContext:context flipped:NO];
		[NSGraphicsContext setCurrentContext:ctx];
	} else {
		// Fallback on earlier versions
		NSGraphicsContext* ctx = [NSGraphicsContext graphicsContextWithGraphicsPort:context flipped:NO];
		[NSGraphicsContext setCurrentContext:ctx];
	}

	[self fillStartingAtPoint:sp startRadius:sr endingAtPoint:ep endRadius:er];

	[NSGraphicsContext restoreGraphicsState];
}

#pragma mark -

- (NSColor*)colorAtValue:(CGFloat)val
{
	// public method to get colour at any point from 0->1 across the gradient. Note that this methiod allows arbitrary
	// (unordered) values of <val> and so is slower than the shader callback. It also creates a calibrated NSColor object
	// that also substantially reduces performance

	NSInteger keys = [self countOfColorStops];

	if (keys < 2) {
		// deal with case where gradient hasn't really been set up properly (0 or 1 Color stops)

		if (keys == 0)
			return [NSColor rgbGrey:0.5];
		else
			return [[[self colorStops] objectAtIndex:0] color];
	} else {
		if (val < 1.0) {
			CGFloat components[4];

			[self private_colorAtValue:val
							components:components
						  randomAccess:YES];
			return [NSColor colorWithCalibratedRed:components[0]
											 green:components[1]
											  blue:components[2]
											 alpha:components[3]];
		} else
			return [[[self colorStops] lastObject] color];
	}
}

#pragma mark -

/** @brief Sets the gradient's current angle in radians
 @param ang the desired angle in radians
 */
- (void)setAngle:(CGFloat)ang
{
	[[NSNotificationCenter defaultCenter] postNotificationName:kDKNotificationGradientWillChange
														object:self];
	m_gradAngle = ang;
	[[NSNotificationCenter defaultCenter] postNotificationName:kDKNotificationGradientDidChange
														object:self];
}

@synthesize angle = m_gradAngle;

/** @brief Sets the angle of the gradient to the given angle
 @param degrees the desired angle expressed in degrees
 */
- (void)setAngleInDegrees:(CGFloat)degrees
{
	[self setAngle:(degrees * M_PI) / 180.0];
}

/** @brief Returns the gradient's current angle in degrees
 @return angle expressed in degrees
 */
- (CGFloat)angleInDegrees
{
	return fmod(([self angle] * 180.0) / M_PI, 360.0);
}

- (void)setAngleWithoutNotifying:(CGFloat)ang
{
	m_gradAngle = ang;
}

#pragma mark -

/** @brief Sets the gradient's basic type

 Valid types are: kDKGradientTypeLinear and kDKGradientTypeRadial
 @param gt the type
 */
- (void)setGradientType:(DKGradientType)gt
{
	if (gt != m_gradType) {
		[[NSNotificationCenter defaultCenter] postNotificationName:kDKNotificationGradientWillChange
															object:self];
		m_gradType = gt;

		// if setting to radial style, should set initial values of radius and starting points in the extended data

		if (gt == kDKGradientTypeRadial && ![self hasRadialSettings]) {
			[self setRadialStartingPoint:NSMakePoint(0.5, 0.5)];
			[self setRadialEndingPoint:NSMakePoint(0.5, 0.5)];
			[self setRadialStartingRadius:0.0];
			[self setRadialEndingRadius:0.5];
		}

		[[NSNotificationCenter defaultCenter] postNotificationName:kDKNotificationGradientDidChange
															object:self];
	}
}

@synthesize gradientType = m_gradType;

#pragma mark -

/** @brief Sets the blending mode for the gradient

 Valid types are: kDKGradientRGBBlending and kDKGradientHSBBlending
 @param bt the blending mode
 */
- (void)setGradientBlending:(DKGradientBlending)bt
{
	if (bt != m_blending) {
		[[NSNotificationCenter defaultCenter] postNotificationName:kDKNotificationGradientWillChange
															object:self];
		m_blending = bt;
		[[NSNotificationCenter defaultCenter] postNotificationName:kDKNotificationGradientDidChange
															object:self];
	}
}

@synthesize gradientBlending = m_blending;

#pragma mark -

/** @brief Sets the interpolation algorithm for the gradient
 @param intrp one of the standard interpolation constants
 */
- (void)setGradientInterpolation:(DKGradientInterpolation)intrp
{
	if (intrp != m_interp) {
		[[NSNotificationCenter defaultCenter] postNotificationName:kDKNotificationGradientWillChange
															object:self];
		m_interp = intrp;
		[[NSNotificationCenter defaultCenter] postNotificationName:kDKNotificationGradientDidChange
															object:self];
	}
}

@synthesize gradientInterpolation = m_interp;

#pragma mark -

- (NSImage*)swatchImageWithSize:(NSSize)size withBorder:(BOOL)showBorder
{
	NSImage* swatchImage = [[NSImage alloc] initWithSize:size];
	NSRect box = NSMakeRect(0.0, 0.0, size.width, size.height);

	[swatchImage lockFocusFlipped:YES];
	[self fillRect:box];

	if (showBorder) {
		[[NSColor grayColor] set];
		NSFrameRectWithWidth(box, 1.0);
	}
	[swatchImage unlockFocus];

	return swatchImage;
}

- (NSImage*)standardSwatchImage
{
	return [self swatchImageWithSize:DKGradientSwatchSize
						  withBorder:YES];
}

#pragma mark -
- (void)colorStopWillChangeColor:(DKColorStop*)stop
{
#pragma unused(stop)
}

- (void)colorStopDidChangeColor:(DKColorStop*)stop
{
#pragma unused(stop)

	//	LogEvent_(kStateEvent, @"stop changed color (%@)", stop);
}

- (void)colorStopWillChangePosition:(DKColorStop*)stop
{
#pragma unused(stop)
}

- (void)colorStopDidChangePosition:(DKColorStop*)stop
{
#pragma unused(stop)

	//	LogEvent_(kStateEvent, @"stop changed position (%@)", stop);
}

#pragma mark -
#pragma mark As a GCObservableObject

/** @brief Sets up KVO for handling undo when this object is used as part of a renderer tree
 @param object the nominated observer
 */
- (BOOL)setUpKVOForObserver:(id)object
{
	if ([super setUpKVOForObserver:object]) {
		[self addObserver:object
			   forKeyPath:@"gradientType"
				  options:NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew
				  context:nil];
		[self addObserver:object
			   forKeyPath:@"angle"
				  options:NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew
				  context:nil];
		[self addObserver:object
			   forKeyPath:@"colorStops"
				  options:NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew
				  context:nil];

		[self setActionName:@"Change Gradient Type"
				 forKeyPath:@"gradientType"];
		[self setActionName:@"Change Gradient Angle"
				 forKeyPath:@"angle"];
		[self setActionName:@"#kind# Gradient Stop"
				 forKeyPath:@"colorStops"];

		// add the observer to any existing stops at this time.

		NSIndexSet* ix = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [self countOfColorStops])];

		[[self colorStops] addObserver:object
					toObjectsAtIndexes:ix
							forKeyPath:@"color"
							   options:NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew
							   context:nil];
		[[self colorStops] addObserver:object
					toObjectsAtIndexes:ix
							forKeyPath:@"position"
							   options:NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew
							   context:nil];

		[GCObservableObject registerActionName:@"Change Gradient Stop Colour"
									forKeyPath:@"color"
									  objClass:[DKColorStop class]];
		[GCObservableObject registerActionName:@"Move Gradient Stop Position"
									forKeyPath:@"position"
									  objClass:[DKColorStop class]];
		return YES;
	} else
		return NO;
}

/** @brief Tears down KVO for handling undo when this object is used as part of a renderer tree
 @param object the nominated observer
 */
- (BOOL)tearDownKVOForObserver:(id)object
{
	if ([super tearDownKVOForObserver:object]) {
		[self removeObserver:object
				  forKeyPath:@"gradientType"];
		[self removeObserver:object
				  forKeyPath:@"angle"];
		[self removeObserver:object
				  forKeyPath:@"colorStops"];

		NSIndexSet* ix = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [self countOfColorStops])];

		[[self colorStops] removeObserver:object
					 fromObjectsAtIndexes:ix
							   forKeyPath:@"color"];
		[[self colorStops] removeObserver:object
					 fromObjectsAtIndexes:ix
							   forKeyPath:@"position"];

		return YES;
	} else
		return NO;
}

#pragma mark -
#pragma mark As an NSObject

- (void)dealloc
{
	[self removeAllColors];
}

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		m_colorStops = [[NSMutableArray alloc] init];

		if (m_colorStops == nil) {
			return nil;
		}
	}
	return self;
}

#pragma mark -
#pragma mark As part of GraphicsAttributes Protocol

/** @brief Adds Color stops from anonymous script parameters

 Supports style scripting for the gradient object
 @param val a value object
 @param pnum the index of the parameter
 */

/** @brief Set up from anonymous parameters in script
 @param val the value
 @param pnum parameter index
 */
- (void)setValue:(id)val forNumericParameter:(NSInteger)pnum
{
#pragma unused(pnum)

	// supports the parser by assigning each anonymous Color stop. <val> will be a DKColorStop

	if ([val isKindOfClass:[DKColorStop class]])
		[self addColorStop:val];
}

#pragma mark -
#pragma mark As part of NSCoding Protocol
- (void)encodeWithCoder:(NSCoder*)coder
{
	NSAssert(coder != nil, @"Expected valid coder");
	[coder encodeObject:[self colorStops]
				 forKey:@"gradientStops"];
	[coder encodeObject:m_extensionData
				 forKey:@"extension_data"];

	[coder encodeDouble:m_gradAngle
				 forKey:@"gradientAngle"];
	[coder encodeInteger:m_gradType
				  forKey:@"gradientType"];
	[coder encodeInteger:[self gradientBlending]
				  forKey:@"blending"];
	[coder encodeInteger:[self gradientInterpolation]
				  forKey:@"interpolation"];
}

- (instancetype)initWithCoder:(NSCoder*)coder
{
	NSAssert(coder != nil, @"Expected valid coder");
	self = [super init];
	if (self != nil) {
		[self setColorStops:[coder decodeObjectForKey:@"gradientStops"]];
		m_extensionData = [[coder decodeObjectForKey:@"extension_data"] mutableCopy];

		m_gradAngle = [coder decodeDoubleForKey:@"gradientAngle"];
		m_gradType = [coder decodeIntegerForKey:@"gradientType"];
		[self setGradientBlending:[coder decodeIntegerForKey:@"blending"]];
		[self setGradientInterpolation:[coder decodeIntegerForKey:@"interpolation"]];

		if (m_colorStops == nil) {
			return nil;
		}

		[self convertOldKeys];
	}

	return self;
}

#pragma mark -
#pragma mark As part of NSCopying Protocol
- (id)copyWithZone:(NSZone*)zone
{
#pragma unused(zone)

	DKGradient* grad = [[[self class] alloc] init];
	grad->m_gradType = m_gradType;
	grad->m_gradAngle = m_gradAngle;
	grad->m_blending = m_blending;
	grad->m_interp = m_interp;

	[grad removeAllColors];

	for (DKColorStop* stop in [self colorStops]) {
		DKColorStop* stopCopy = [stop copy];
		[grad addColorStop:stopCopy];
	}

	grad->m_extensionData = [m_extensionData mutableCopy];

	return grad;
}

@end

#pragma mark -
@implementation DKColorStop
#pragma mark As a DKColorStop

- (instancetype)initWithColor:(NSColor*)Color at:(CGFloat)pos
{
	self = [super init];
	if (self != nil) {
		[self setColor:Color];
		[self setPosition:pos];
		NSAssert(m_ownerRef == nil, @"Expected init to zero");

		if (mColor == nil) {
			return nil;
		}
	}
	return self;
}

#pragma mark -

@synthesize color = mColor;

/** @brief Set the Color associated with this stop

 Colors are converted to calibrated RGB to permit shading calculations
 @param aColor the Color to set
 */
- (void)setColor:(NSColor*)aColor
{
	[[self owner] colorStopWillChangeColor:self];

	NSColor* rgb = [aColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace];

	mColor = rgb;

	// cache the components so that they can be rapidly accessed when plotting the shading

	[rgb getRed:&components[0]
		  green:&components[1]
		   blue:&components[2]
		  alpha:&components[3]];
	[[self owner] colorStopDidChangeColor:self];
}

- (void)setAlpha:(CGFloat)alpha
{
	self.color = [self.color colorWithAlphaComponent:alpha];
}

- (CGFloat)alpha
{
	return self.color.alphaComponent;
}

#pragma mark -

@synthesize position;

/** @brief Set the stop's relative position

 Value is constrained between 0.0 and 1.0
 @param pos a vlue between 0 and 1
 */
- (void)setPosition:(CGFloat)pos
{
	[[self owner] colorStopWillChangePosition:self];
	position = LIMIT(pos, 0.0, 1.0);
	[[self owner] colorStopDidChangePosition:self];
}

#pragma mark -
@synthesize owner = m_ownerRef;

#pragma mark -
#pragma mark As an NSObject

#pragma mark -
#pragma mark As part of GraphicsAttributes Protocol

- (void)setValue:(id)val forNumericParameter:(NSInteger)pnum
{
	// supports the parser by assigning param 0 -> position, param 1 -> Color

	if (pnum == 0)
		[self setPosition:[val doubleValue]];
	else if (pnum == 1)
		[self setColor:val];
}

#pragma mark -
#pragma mark As part of NSCoding Protocol
- (void)encodeWithCoder:(NSCoder*)coder
{
	NSAssert(coder != nil, @"Expected valid coder");
	[coder encodeObject:[self color]
				 forKey:@"color"];
	[coder encodeDouble:[self position]
				 forKey:@"position"];
	[coder encodeConditionalObject:[self owner]
							forKey:@"DKColorStop_owner"];
}

- (instancetype)initWithCoder:(NSCoder*)coder
{
	NSAssert(coder != nil, @"Expected valid coder");
	self = [super init];
	if (self != nil) {
		[self setColor:[coder decodeObjectForKey:@"color"]];
		[self setPosition:[coder decodeDoubleForKey:@"position"]];
		[self setOwner:[coder decodeObjectForKey:@"DKColorStop_owner"]];

		if (mColor == nil) {
			return nil;
		}
	}
	return self;
}

#pragma mark -
#pragma mark As part of NSCopying Protocol
- (id)copyWithZone:(NSZone*)zone
{
	return [[DKColorStop allocWithZone:zone] initWithColor:[self color]
														at:[self position]];
}

@end

#pragma mark -

static inline double powerMap(double x, double y)
{
	if (y == 0.0)
		y = 1.0;

	if (y < 0)
		return 1.0 - pow(1.0 - x, -y);
	else
		return pow(x, y);
}

static inline double sineMap(double x, double y)
{
	if (y < 0)
		return sin(x * M_PI_2 + 3.0 * M_PI_2) + 1.0;
	else
		return sin(x * M_PI_2);
}

static inline void transformHSV_RGB(CGFloat* components) //H,S,B -> R,G,B
{
	CGFloat R, G, B;
	CGFloat H = fmod(components[0], 359), //map to [0,360)
		S = components[1],
			V = components[2];

	NSInteger Hi = (NSInteger)floor(H / 60.) % 6;
	CGFloat f = H / 60 - Hi,
			p = V * (1 - S),
			q = V * (1 - f * S),
			t = V * (1 - (1 - f) * S);

	switch (Hi) {
	default:
	case 0:
		R = V;
		G = t;
		B = p;
		break;
	case 1:
		R = q;
		G = V;
		B = p;
		break;
	case 2:
		R = p;
		G = V;
		B = t;
		break;
	case 3:
		R = p;
		G = q;
		B = V;
		break;
	case 4:
		R = t;
		G = p;
		B = V;
		break;
	case 5:
		R = V;
		G = p;
		B = q;
		break;
	}

	components[0] = R;
	components[1] = G;
	components[2] = B;
}

static inline void transformRGB_HSV(CGFloat* components) //H,S,B -> R,G,B
{
	CGFloat H = 0.0;
	CGFloat S, V;
	CGFloat R = components[0],
			G = components[1],
			B = components[2];

	CGFloat MAX = R > G ? (R > B ? R : B) : (G > B ? G : B),
			MIN = R < G ? (R < B ? R : B) : (G < B ? G : B);

	if (MAX == MIN)
		H = NAN;
	else if (MAX == R)
		if (G >= B)
			H = 60 * (G - B) / (MAX - MIN) + 0;
		else
			H = 60 * (G - B) / (MAX - MIN) + 360;
	else if (MAX == G)
		H = 60 * (B - R) / (MAX - MIN) + 120;
	else if (MAX == B)
		H = 60 * (R - G) / (MAX - MIN) + 240;

	S = MAX == 0 ? 0 : 1 - MIN / MAX;
	V = MAX;

	components[0] = H;
	components[1] = S;
	components[2] = V;
}

static inline void resolveHSV(CGFloat* color1, CGFloat* color2)
{
	if (isnan(color1[0]) && isnan(color2[0]))
		color1[0] = color2[0] = 0;
	else if (isnan(color1[0]))
		color1[0] = color2[0];
	else if (isnan(color2[0]))
		color2[0] = color1[0];
}
