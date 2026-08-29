//this CRT effect shader by Matt Halford demonstrates the shadertoy template.
//the code in here is copy-pasted from the shadertoy web site: https://www.shadertoy.com/view/llsfD8
//you'll have to create a custom dstack if you want to add things like custom parameters and more textures.

// Simple CRT Video Effect
// @author	Matt Halford	matt@resn.co.nz

// Applys a CRT effect including bulge distortion, vignette, scan lines, indirect moire effects,
// color abberation near edges and video rolling effect


// Util Functions

// getCenterDistance
// Gets Distance between points in the coord space and the center of that space
// @param	vec2	coord		coordinate space to caculate distance to center
// @return	float				distance from center of plane (0 in center, -1 and 1 at edges)
float getCenterDistance(vec2 coord)
{
    return distance(coord, vec2(0.5)) * 2.0; //return difference between point on screen and the center with -1 and 1 at either edge
}


// Sample Distortion Functions

// videoRollCoords
// Rolls Coordinates to perform an old fashioned CRT rolling effect
// @param	vec2	coord		coordinates to distort
// @param	float	speed		speed to translate image (loops per second)
// @param	float	amount		fraction of the period during which rolling occurs (0 - 1)
// @param	float	period		period of rolling effect repetition (in seconds)
// @return	vec2				distorted sample coordinates
vec2 videoRollCoords(vec2 coord, float speed, float amount, float period)
{
    float scrolling = step(0.0, sin(iTime * 6.28 / period) * 0.5 + (-0.5 + amount)); //set scrolling to 1 if frequency sin wave is above 0
    
    coord.y -= iTime * speed * scrolling; //if scrolling offset y coord over time
	coord = fract(coord); //keep coord to fractional component so not multiplying crazily when applying later coord distance comparisons 
    
    return coord;
}

// bulgeCoords
// Bulges Coordinates to perform a bulging lens effect
// @param	vec2	coord		coordinates to distort
// @param	vec2	sourceCoord	source coordinate space to caculate distance to center
// @param 	float	bulgeAmount	amount to bulge coordindates
// @return	vec2				distorted sample coordinates
vec2 bulgeCoords(vec2 coord, vec2 sourceCoord, float bulgeAmount)
{
    float centerDist = getCenterDistance(sourceCoord);
    
    coord.xy -= vec2(0.5); //reposition so scaling performed from center of image
    
    coord.xy *= 1.0 + centerDist * bulgeAmount; //scale up coordinates the further from center they are
    coord.xy *= 1.0 - bulgeAmount; //scale down oversampling to reduce tiling
    
    coord.xy += vec2(0.5); //restore position to center of view
    
	coord = clamp(coord, 0.0f, 1.0f);
	
    return coord;
}


// Sample Functions

// sampleRGBVignette
// Samples texture pixels with RGB color abberation shift towards the edges of the view, simulating lens color abberation
// @param	sampler2D	source		source texture to sample
// @param	vec2		coord		coordinates to distort
// @param	vec2		sourceCoord	source coordinate space to caculate distance to center
// @param 	float		amount		amount to offset Green and Blue channels (B offset twice as far from R)
// @param 	float		power		bias of color abberation just towards edges of view (>= 1)
// @return	vec4					resultant sample color with color RGB abberation
vec4 sampleRGBVignette(sampler2D source, vec2 coord, vec2 sourceCoord, float amount, float power)
{
    float centerDist = getCenterDistance(sourceCoord);
    centerDist = pow(centerDist, power); //bias distance from center to ramp up steeper towards edges
    
    vec2 sampleCoord = coord;
    vec4 outputColor = texture(source, fract(sampleCoord)); //get default sample image (for R)
    
    sampleCoord = bulgeCoords(coord, sourceCoord, amount * centerDist); //bulge sample coordinates by amount, multiply by center distance to reduce effect in center
    outputColor.g = texture(source, fract(sampleCoord)).g; //sample Green amount by G color abberation
    
    sampleCoord = bulgeCoords(coord, sourceCoord, amount * 2.0 * centerDist); //bulge sample coordinates by double amount for Blue (twice as far from R as G)
    outputColor.b = texture(source, fract(sampleCoord)).b; //sample Blue amount by B color abberation
    
    return outputColor;
}


//Color Effect Functions

// applyScanLines
// Applys darkened horizontal scan line gaps to simulate a CRT effect
// @param	vec4		color		original color value
// @param	vec2		coord		coordinate space for scan lines (could be pre-distorted, e.g. with bulgeCoords)
// @param	float		number		number of scan lines across vertical view
// @param 	float		amount		amount to darken gaps between scan lines (0 - 1)
// @param 	float		power		bias of illuminated scan lines to gaps (> 1 = wider bright lights, < 1 wider gaps)
// @param 	float		drift		speed of vertical drift in line positions (loops per second)
// @return	vec4					resultant color with scan line gaps applied
vec4 applyScanLines(vec4 color, vec2 coord, float number, float amount, float power, float drift)
{
    coord.y += iTime * drift; //animate scrolling coordinates (great for shifting moire effects with high number of lines)
    
    float darkenAmount = 0.5 + 0.5 * cos(coord.y * 6.28 * number); //get darken amount as cos wave between 0 and 1, over number of lines across height
    darkenAmount = pow(darkenAmount, power); //bias darkenAmount towards wider light areas
        
    color.rgb -= darkenAmount * amount; //darken rgb colors by given gap darkness amount
        
    return color;
}

// applyVignette
// Applys darkened vignette to edges of view
// @param	vec4		color		original color value
// @param	vec2		coord		source coordinate space to caculate distance to center
// @param 	float		amount		amount to darken gaps vignette edges
// @param 	float		scale		scale of vignette outer ellipse (1 = darkest at ellipse incribing view)
// @param 	float		power		bias vignette fade towards edges of ellipse (>= 1)
// @return	vec4					resultant color with vignette applied
vec4 applyVignette(vec4 color, vec2 sourceCoord, float amount, float scale, float power)
{
    float centerDist = getCenterDistance(sourceCoord);
    
    float darkenAmount = centerDist / scale; //get amount to darken current fragment by scaled distance from center
    
    darkenAmount = pow(darkenAmount, power); //bias darkenAmount towards edges of distance
    
    darkenAmount = min(1.0, darkenAmount); //clamp maximum darkenAmount to 1 so amount param can lighten outer regions of vignette 
    
    color.rgb -= darkenAmount * amount; //darken rgb colors by given vignette amount
    
    return color;
}


// Main Fragment Processing

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    vec2 sourceCoord = fragCoord.xy / iResolution.xy; //get sourceCoords in range 0 - 1
    
    vec2 sampleCoord = sourceCoord;
    
	//this bit is disabled here in case anyone wants to actually try playing with this shader and not vomiting
    //sampleCoord = videoRollCoords(sampleCoord, 5.0, 0.2, 2.0); //apply video rolling effect to sample coords
    sampleCoord = bulgeCoords(sampleCoord, sourceCoord, 0.1); //apply bulge effect to sample coords
    
    //vec4 outputColor = texture(iChannel0, fract(sampleCoord)); //to sample without RGB color abberation
    
    vec4 outputColor = sampleRGBVignette(iChannel0, sampleCoord, sourceCoord, 0.1, 2.0); //sample bulged coords with color abberation
    
    float vignetteAmount = 1.2 + 0.05 * sin(iTime * 50.0); //set a fluctuating vignette intensity
    outputColor = applyVignette(outputColor, sourceCoord, vignetteAmount, 2.0, 2.5); //apply vignette to sampled color
    
    vec2 scanLineCoord = bulgeCoords(sourceCoord, sourceCoord, 0.2);  //get bulged coords to bulge scan lines
    outputColor = applyScanLines(outputColor, scanLineCoord, 150.0, 0.25, 2.0, 0.01); //apply scan lines (with bulged coords)
    
    //outputColor = texture(iChannel0, fract(sourceCoord)); //to preview texture without effects
    
    fragColor = outputColor; //output resultant fragment color
}
