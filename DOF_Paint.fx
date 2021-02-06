#include "ReShade.fxh"
#include "ReShadeUI.fxh"

uniform float2 mouse_point < source = "mousepoint"; > ;
uniform float frametime < source = "frametime"; > ;

// UI uniforms
uniform float blurMult <
	ui_type = "drag";
	ui_min = 0.0;
	ui_step = 0.01;
	ui_label = "Blur size";
	ui_tooltip = "Value multiplied to blur radius.\n0 means no blur, higher values increase blur radius.\nNon 0 values do not impact performance.";
> = 5.0;

uniform float focusDist <
    ui_type = "drag";
    ui_min = 0.0; ui_max = 1.0;
    ui_label = "Manual focus distance";
	ui_tooltip = "Distance to focus on when using manual focus.\n0 means closest to camera, 1 means farthest from camera.\nNo consistant impact on performance.";
> = 0.5;

uniform bool autoFocus <
	ui_type = "radio";
	ui_label = "Enable auto-focus";
	ui_tooltip = "Enables auto-focus, which focuses on a specific point/area.\nWhen disabled, focuses on the depth from manual focus distance.\nPerformance impact is relative to focus are size, and can be significant.";
> = true;

uniform float focusSpeed <
	ui_type = "drag";
	ui_min = 0.0;
	ui_label = "Focus speed";
	ui_tooltip = "Speed the auto focus will transition different focuses, in milliseconds.\n0 means instant transition. No performance impact.";
> = 500.0;

uniform int focusPointSize <
	ui_type = "drag";
	ui_min = 0; ui_max = BUFFER_HEIGHT;
	ui_label = "Auto-focus area size";
	ui_tooltip = "Size of the are to look at when focusing.\nAuto-focus will focus on the closest object in the area.\n0 will focus on a single point.\nHigher values will significantly decrease performance.";
> = 100;

uniform float2 focusPoint <
	ui_type = "drag";
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "Auto-focus center";
	ui_tooltip = "The center of the area to auto-focus on. No performance impact.\nFor left value (x) 0 is left of screen, 1 is right. For right value (y), 0 is top of screen, 1 is bottom.";
> = float2(0.5, 0.5);

uniform int blurType <
	ui_type = "combo";
	ui_items = "High Quality Circle\0Medium Quality Circle\0Low Quality Circle\0High Quality Diamond\0Medium Quality Diamond\0Low Quality Diamond\0High Quality Hexagon\0Medium Quality Hexagon\0Low Quality Hexagon\0Painted Look\0";
	ui_label = "Blur shape / quality";
	ui_tooltip = "Shape and quality of the bokeh blur. Higher quality values have a significant impact on performance while increasing blur quality.";
> = 0;

uniform bool disableNear <
	ui_type = "radio";
	ui_label = "Disable foreground blur";
	ui_tooltip = "Disables foreground bluring, so that only objects in the foreground are always in focus.\nCan improve performance depending on the scene.";
> = false;

uniform bool showFocusArea <
	ui_type = "radio";
	ui_label = "Show focus area";
	ui_tooltip = "Highlights the area of the screen being searched by auto-focus.";
> = false;

uniform bool mouseFocus <
	ui_type = "radio";
	ui_label = "Focus on mouse position";
	ui_tooltip = "Focuses on whatever object is being hovered over by the mouse. Requires auto-focus to be enabled.\nIs not affected by focus area size, but otherwise has no impact on performance.";
> = false;

// Buffer which stores CoC values
texture cocBuffer{ Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT;  Format = R16F; MipLevels = 0;};
sampler2D cocSampler{ Texture = cocBuffer; MipFilter = POINT;};

// Buffers and samplers which store and read the focus value in a 1x1 texture (used like a float)
texture2D focusTex{ Width = 1; Height = 1; Format = R16F; };
texture2D focusTexPrev{ Width = 1; Height = 1; Format = R16F; };

sampler2D focusTexSampler{ Texture = focusTex; };
sampler2D focusTexPrevSampler{ Texture = focusTexPrev; };

// Kernels for blur effect
static const float2 kernel[244] = {
	// High Quality Circle
	float2(0,0),
	float2(0.36363637 / BUFFER_WIDTH,0),
	float2(0.22672357 / BUFFER_WIDTH,0.28430238 / BUFFER_HEIGHT),
	float2(-0.08091671 / BUFFER_WIDTH,0.35451925 / BUFFER_HEIGHT),
	float2(-0.32762504 / BUFFER_WIDTH,0.15777594 / BUFFER_HEIGHT),
	float2(-0.32762504 / BUFFER_WIDTH,-0.15777591 / BUFFER_HEIGHT),
	float2(-0.08091656 / BUFFER_WIDTH,-0.35451928 / BUFFER_HEIGHT),
	float2(0.22672352 / BUFFER_WIDTH,-0.2843024 / BUFFER_HEIGHT),
	float2(0.6818182 / BUFFER_WIDTH,0),
	float2(0.614297 / BUFFER_WIDTH,0.29582983 / BUFFER_HEIGHT),
	float2(0.42510667 / BUFFER_WIDTH,0.5330669 / BUFFER_HEIGHT),
	float2(0.15171885 / BUFFER_WIDTH,0.6647236 / BUFFER_HEIGHT),
	float2(-0.15171883 / BUFFER_WIDTH,0.6647236 / BUFFER_HEIGHT),
	float2(-0.4251068 / BUFFER_WIDTH,0.53306687 / BUFFER_HEIGHT),
	float2(-0.614297 / BUFFER_WIDTH,0.29582986 / BUFFER_HEIGHT),
	float2(-0.6818182 / BUFFER_WIDTH,0),
	float2(-0.614297 / BUFFER_WIDTH,-0.29582983 / BUFFER_HEIGHT),
	float2(-0.42510656 / BUFFER_WIDTH,-0.53306705 / BUFFER_HEIGHT),
	float2(-0.15171856 / BUFFER_WIDTH,-0.66472363 / BUFFER_HEIGHT),
	float2(0.1517192 / BUFFER_WIDTH,-0.6647235 / BUFFER_HEIGHT),
	float2(0.4251066 / BUFFER_WIDTH,-0.53306705 / BUFFER_HEIGHT),
	float2(0.614297 / BUFFER_WIDTH,-0.29582983 / BUFFER_HEIGHT),
	float2(1. / BUFFER_WIDTH,0),
	float2(0.9555728 / BUFFER_WIDTH,0.2947552 / BUFFER_HEIGHT),
	float2(0.82623875 / BUFFER_WIDTH,0.5633201 / BUFFER_HEIGHT),
	float2(0.6234898 / BUFFER_WIDTH,0.7818315 / BUFFER_HEIGHT),
	float2(0.36534098 / BUFFER_WIDTH,0.93087375 / BUFFER_HEIGHT),
	float2(0.07473 / BUFFER_WIDTH,0.9972038 / BUFFER_HEIGHT),
	float2(-0.22252095 / BUFFER_WIDTH,0.9749279 / BUFFER_HEIGHT),
	float2(-0.50000006 / BUFFER_WIDTH,0.8660254 / BUFFER_HEIGHT),
	float2(-0.73305196 / BUFFER_WIDTH,0.6801727 / BUFFER_HEIGHT),
	float2(-0.90096885 / BUFFER_WIDTH,0.43388382 / BUFFER_HEIGHT),
	float2(-0.98883086 / BUFFER_WIDTH,0.14904208 / BUFFER_HEIGHT),
	float2(-0.9888308 / BUFFER_WIDTH,-0.14904249 / BUFFER_HEIGHT),
	float2(-0.90096885 / BUFFER_WIDTH,-0.43388376 / BUFFER_HEIGHT),
	float2(-0.73305184 / BUFFER_WIDTH,-0.6801728 / BUFFER_HEIGHT),
	float2(-0.4999999 / BUFFER_WIDTH,-0.86602545 / BUFFER_HEIGHT),
	float2(-0.222521 / BUFFER_WIDTH,-0.9749279 / BUFFER_HEIGHT),
	float2(0.07473029 / BUFFER_WIDTH,-0.99720377 / BUFFER_HEIGHT),
	float2(0.36534148 / BUFFER_WIDTH,-0.9308736 / BUFFER_HEIGHT),
	float2(0.6234897 / BUFFER_WIDTH,-0.7818316 / BUFFER_HEIGHT),
	float2(0.8262388 / BUFFER_WIDTH,-0.56332 / BUFFER_HEIGHT),
	float2(0.9555729 / BUFFER_WIDTH,-0.29475483 / BUFFER_HEIGHT),

	// Medium Quality Circle
	float2(0, 0),
	float2(0.53333336 / BUFFER_WIDTH, 0),
	float2(0.3325279 / BUFFER_WIDTH, 0.4169768 / BUFFER_HEIGHT),
	float2(-0.11867785 / BUFFER_WIDTH, 0.5199616 / BUFFER_HEIGHT),
	float2(-0.48051673 / BUFFER_WIDTH, 0.2314047 / BUFFER_HEIGHT),
	float2(-0.48051673 / BUFFER_WIDTH, -0.23140468 / BUFFER_HEIGHT),
	float2(-0.11867763 / BUFFER_WIDTH, -0.51996166 / BUFFER_HEIGHT),
	float2(0.33252785 / BUFFER_WIDTH, -0.4169769 / BUFFER_HEIGHT),
	float2(1. / BUFFER_WIDTH, 0),
	float2(0.90096885 / BUFFER_WIDTH, 0.43388376 / BUFFER_HEIGHT),
	float2(0.6234898 / BUFFER_WIDTH, 0.7818315 / BUFFER_HEIGHT),
	float2(0.22252098 / BUFFER_WIDTH, 0.9749279 / BUFFER_HEIGHT),
	float2(-0.22252095 / BUFFER_WIDTH, 0.9749279 / BUFFER_HEIGHT),
	float2(-0.62349 / BUFFER_WIDTH, 0.7818314 / BUFFER_HEIGHT),
	float2(-0.90096885 / BUFFER_WIDTH, 0.43388382 / BUFFER_HEIGHT),
	float2(-1. / BUFFER_WIDTH, 0),
	float2(-0.90096885 / BUFFER_WIDTH, -0.43388376 / BUFFER_HEIGHT),
	float2(-0.6234896 / BUFFER_WIDTH, -0.7818316 / BUFFER_HEIGHT),
	float2(-0.22252055 / BUFFER_WIDTH, -0.974928 / BUFFER_HEIGHT),
	float2(0.2225215 / BUFFER_WIDTH, -0.9749278 / BUFFER_HEIGHT),
	float2(0.6234897 / BUFFER_WIDTH, -0.7818316 / BUFFER_HEIGHT),
	float2(0.90096885 / BUFFER_WIDTH, -0.43388376 / BUFFER_HEIGHT),

	// Low Quality Circle
	float2(0, 0),
	float2(0.54545456 / BUFFER_WIDTH, 0),
	float2(0.16855472 / BUFFER_WIDTH, 0.5187581 / BUFFER_HEIGHT),
	float2(-0.44128203 / BUFFER_WIDTH, 0.3206101 / BUFFER_HEIGHT),
	float2(-0.44128197 / BUFFER_WIDTH, -0.3206102 / BUFFER_HEIGHT),
	float2(0.1685548 / BUFFER_WIDTH, -0.5187581 / BUFFER_HEIGHT),
	float2(1. / BUFFER_WIDTH, 0),
	float2(0.809017 / BUFFER_WIDTH, 0.58778524 / BUFFER_HEIGHT),
	float2(0.30901697 / BUFFER_WIDTH, 0.95105654 / BUFFER_HEIGHT),
	float2(-0.30901703 / BUFFER_WIDTH, 0.9510565 / BUFFER_HEIGHT),
	float2(-0.80901706 / BUFFER_WIDTH, 0.5877852 / BUFFER_HEIGHT),
	float2(-1. / BUFFER_WIDTH, 0),
	float2(-0.80901694 / BUFFER_WIDTH, -0.58778536 / BUFFER_HEIGHT),
	float2(-0.30901664 / BUFFER_WIDTH, -0.9510566 / BUFFER_HEIGHT),
	float2(0.30901712 / BUFFER_WIDTH, -0.9510565 / BUFFER_HEIGHT),
	float2(0.80901694 / BUFFER_WIDTH, -0.5877853 / BUFFER_HEIGHT),

	// High Quality Diamond
	float2(0., 0.),
	float2(.666667 / BUFFER_WIDTH, 0),
	float2(-.666667 / BUFFER_WIDTH, 0),
	float2(0, .666667 / BUFFER_HEIGHT),
	float2(0, -.666667 / BUFFER_HEIGHT),
	float2(.333333 / BUFFER_WIDTH, .333333 / BUFFER_HEIGHT),
	float2(-.333333 / BUFFER_WIDTH, .333333 / BUFFER_HEIGHT),
	float2(.333333 / BUFFER_WIDTH, -.333333 / BUFFER_HEIGHT),
	float2(-.333333 / BUFFER_WIDTH, -.333333 / BUFFER_HEIGHT),
	float2(-.333333 / BUFFER_WIDTH, 0),
	float2(0, .333333 / BUFFER_HEIGHT),
	float2(.333333 / BUFFER_WIDTH, 0),
	float2(0, -.333333 / BUFFER_HEIGHT),
	float2(.166667 / BUFFER_WIDTH, .166667 / BUFFER_HEIGHT),
	float2(-.166667 / BUFFER_WIDTH, .166667 / BUFFER_HEIGHT),
	float2(.166667 / BUFFER_WIDTH, -.166667 / BUFFER_HEIGHT),
	float2(-.166667 / BUFFER_WIDTH, -.166667 / BUFFER_HEIGHT),
	float2(.5 / BUFFER_WIDTH, .166667 / BUFFER_HEIGHT),
	float2(.166667 / BUFFER_WIDTH, .5 / BUFFER_HEIGHT),
	float2(-.166667 / BUFFER_WIDTH, .5 / BUFFER_HEIGHT),
	float2(-.5 / BUFFER_WIDTH, .166667 / BUFFER_HEIGHT),
	float2(-.5 / BUFFER_WIDTH, -.166667 / BUFFER_HEIGHT),
	float2(-.166667 / BUFFER_WIDTH, -.5 / BUFFER_HEIGHT),
	float2(.166667 / BUFFER_WIDTH, -.5 / BUFFER_HEIGHT),
	float2(.5 / BUFFER_WIDTH, -.166667 / BUFFER_HEIGHT),
	float2(1. / BUFFER_WIDTH, 0),
	float2(0, 1. / BUFFER_HEIGHT),
	float2(-1. / BUFFER_WIDTH, 0),
	float2(0, -1. / BUFFER_HEIGHT),
	float2(.833333 / BUFFER_WIDTH, .166667 / BUFFER_HEIGHT),
	float2(.666667 / BUFFER_WIDTH, .333333 / BUFFER_HEIGHT),
	float2(.5 / BUFFER_WIDTH, .5 / BUFFER_HEIGHT),
	float2(.333333 / BUFFER_WIDTH, .666667 / BUFFER_HEIGHT),
	float2(.166667 / BUFFER_WIDTH, .833333 / BUFFER_HEIGHT),
	float2(-.833333 / BUFFER_WIDTH, .166667 / BUFFER_HEIGHT),
	float2(-.666667 / BUFFER_WIDTH, .333333 / BUFFER_HEIGHT),
	float2(-.5 / BUFFER_WIDTH, .5 / BUFFER_HEIGHT),
	float2(-.333333 / BUFFER_WIDTH, .666667 / BUFFER_HEIGHT),
	float2(-.166667 / BUFFER_WIDTH, .833333 / BUFFER_HEIGHT),
	float2(-.833333 / BUFFER_WIDTH, -.166667 / BUFFER_HEIGHT),
	float2(-.666667 / BUFFER_WIDTH, -.333333 / BUFFER_HEIGHT),
	float2(-.5 / BUFFER_WIDTH, -.5 / BUFFER_HEIGHT),
	float2(-.333333 / BUFFER_WIDTH, -.666667 / BUFFER_HEIGHT),
	float2(-.166667 / BUFFER_WIDTH, -.833333 / BUFFER_HEIGHT),
	float2(.833333 / BUFFER_WIDTH, -.166667 / BUFFER_HEIGHT),
	float2(.666667 / BUFFER_WIDTH, -.333333 / BUFFER_HEIGHT),
	float2(.5 / BUFFER_WIDTH, -.5 / BUFFER_HEIGHT),
	float2(.333333 / BUFFER_WIDTH, -.666667 / BUFFER_HEIGHT),
	float2(.166667 / BUFFER_WIDTH, -.833333 / BUFFER_HEIGHT),

	// Medium Quality Diamond
	float2(0., 0.),
	float2(1. / BUFFER_WIDTH, 0),
	float2(-1. / BUFFER_WIDTH, 0),
	float2(0, 1. / BUFFER_HEIGHT),
	float2(0, -1. / BUFFER_HEIGHT),
	float2(.5 / BUFFER_WIDTH, .5 / BUFFER_HEIGHT),
	float2(-.5 / BUFFER_WIDTH, .5 / BUFFER_HEIGHT),
	float2(.5 / BUFFER_WIDTH, -.5 / BUFFER_HEIGHT),
	float2(-.5 / BUFFER_WIDTH, -.5 / BUFFER_HEIGHT),
	float2(-.5 / BUFFER_WIDTH, 0),
	float2(0, .5 / BUFFER_HEIGHT),
	float2(.5 / BUFFER_WIDTH, 0),
	float2(0, -.5 / BUFFER_HEIGHT),
	float2(.25 / BUFFER_WIDTH, .25 / BUFFER_HEIGHT),
	float2(-.25 / BUFFER_WIDTH, .25 / BUFFER_HEIGHT),
	float2(.25 / BUFFER_WIDTH, -.25 / BUFFER_HEIGHT),
	float2(-.25 / BUFFER_WIDTH, -.25 / BUFFER_HEIGHT),
	float2(.75 / BUFFER_WIDTH, .25 / BUFFER_HEIGHT),
	float2(.25 / BUFFER_WIDTH, .75 / BUFFER_HEIGHT),
	float2(-.25 / BUFFER_WIDTH, .75 / BUFFER_HEIGHT),
	float2(-.75 / BUFFER_WIDTH, .25 / BUFFER_HEIGHT),
	float2(-.75 / BUFFER_WIDTH, -.25 / BUFFER_HEIGHT),
	float2(-.25 / BUFFER_WIDTH, -.75 / BUFFER_HEIGHT),
	float2(.25 / BUFFER_WIDTH, -.75 / BUFFER_HEIGHT),
	float2(.75 / BUFFER_WIDTH, -.25 / BUFFER_HEIGHT),

	// Low Quality Diamond
	float2(0., 0.),
	float2(1. / BUFFER_WIDTH, 0),
	float2(-1. / BUFFER_WIDTH, 0),
	float2(0, 1. / BUFFER_HEIGHT),
	float2(0, -1. / BUFFER_HEIGHT),
	float2(.5 / BUFFER_WIDTH, .5 / BUFFER_HEIGHT),
	float2(-.5 / BUFFER_WIDTH, .5 / BUFFER_HEIGHT),
	float2(.5 / BUFFER_WIDTH, -.5 / BUFFER_HEIGHT),
	float2(-.5 / BUFFER_WIDTH, -.5 / BUFFER_HEIGHT),
	float2(-.5 / BUFFER_WIDTH, 0),
	float2(0, .5 / BUFFER_HEIGHT),
	float2(.5 / BUFFER_WIDTH, 0),
	float2(0, -.5 / BUFFER_HEIGHT),

	// High Quality Hexagon
	float2(0., 0.),
	float2(.666667 / BUFFER_WIDTH, 0. / BUFFER_HEIGHT),
	float2(.5 / BUFFER_WIDTH, .288675 / BUFFER_HEIGHT),
	float2(.333333 / BUFFER_WIDTH, .577350 / BUFFER_HEIGHT),
	float2(0. / BUFFER_WIDTH, .577350 / BUFFER_HEIGHT),
	float2(-.333333 / BUFFER_WIDTH, .577350 / BUFFER_HEIGHT),
	float2(-.5 / BUFFER_WIDTH, .288675 / BUFFER_HEIGHT),
	float2(-.666667 / BUFFER_WIDTH, 0. / BUFFER_HEIGHT),
	float2(-.5 / BUFFER_WIDTH, -.288675 / BUFFER_HEIGHT),
	float2(-.333333 / BUFFER_WIDTH, -.577350 / BUFFER_HEIGHT),
	float2(0. / BUFFER_WIDTH, -.577350 / BUFFER_HEIGHT),
	float2(.333333 / BUFFER_WIDTH, -.577350 / BUFFER_HEIGHT),
	float2(.5 / BUFFER_WIDTH, -.288675 / BUFFER_HEIGHT),
	float2(.333333 / BUFFER_WIDTH, 0. / BUFFER_HEIGHT),
	float2(.166667 / BUFFER_WIDTH, .288675 / BUFFER_HEIGHT),
	float2(-.166667 / BUFFER_WIDTH, .288675 / BUFFER_HEIGHT),
	float2(-.333333 / BUFFER_WIDTH, 0. / BUFFER_HEIGHT),
	float2(-.166667 / BUFFER_WIDTH, -.288675 / BUFFER_HEIGHT),
	float2(.166667 / BUFFER_WIDTH, -.288675 / BUFFER_HEIGHT),
	float2(1. / BUFFER_WIDTH, 0. / BUFFER_HEIGHT),
	float2(.5 / BUFFER_WIDTH, .866025 / BUFFER_HEIGHT),
	float2(-.5 / BUFFER_WIDTH, .866025 / BUFFER_HEIGHT),
	float2(-1. / BUFFER_WIDTH, 0. / BUFFER_HEIGHT),
	float2(-.5 / BUFFER_WIDTH, -.866025 / BUFFER_HEIGHT),
	float2(.5 / BUFFER_WIDTH, -.866025 / BUFFER_HEIGHT),
	float2(.833333 / BUFFER_WIDTH, .288675 / BUFFER_HEIGHT),
	float2(.666667 / BUFFER_WIDTH, .577350 / BUFFER_HEIGHT),
	float2(.166667 / BUFFER_WIDTH, .866025 / BUFFER_HEIGHT),
	float2(-.166667 / BUFFER_WIDTH, .866025 / BUFFER_HEIGHT),
	float2(-.833333 / BUFFER_WIDTH, .288675 / BUFFER_HEIGHT),
	float2(-.666667 / BUFFER_WIDTH, .577350 / BUFFER_HEIGHT),
	float2(.833333 / BUFFER_WIDTH, -.288675 / BUFFER_HEIGHT),
	float2(.666667 / BUFFER_WIDTH, -.577350 / BUFFER_HEIGHT),
	float2(.166667 / BUFFER_WIDTH, -.866025 / BUFFER_HEIGHT),
	float2(-.166667 / BUFFER_WIDTH, -.866025 / BUFFER_HEIGHT),
	float2(-.833333 / BUFFER_WIDTH, -.288675 / BUFFER_HEIGHT),
	float2(-.666667 / BUFFER_WIDTH, -.577350 / BUFFER_HEIGHT),

	// Medium Quality Hexagon
	float2(0., 0.),
	float2(1. / BUFFER_WIDTH, 0. / BUFFER_HEIGHT),
	float2(.75 / BUFFER_WIDTH, .433012 / BUFFER_HEIGHT),
	float2(.5 / BUFFER_WIDTH, .866025 / BUFFER_HEIGHT),
	float2(0. / BUFFER_WIDTH, .866025 / BUFFER_HEIGHT),
	float2(-.5 / BUFFER_WIDTH, .866025 / BUFFER_HEIGHT),
	float2(-.75 / BUFFER_WIDTH, .433012 / BUFFER_HEIGHT),
	float2(-1. / BUFFER_WIDTH, 0. / BUFFER_HEIGHT),
	float2(-.75 / BUFFER_WIDTH, -.433012 / BUFFER_HEIGHT),
	float2(-.5 / BUFFER_WIDTH, -.866025 / BUFFER_HEIGHT),
	float2(0. / BUFFER_WIDTH, -.866025 / BUFFER_HEIGHT),
	float2(.5 / BUFFER_WIDTH, -.866025 / BUFFER_HEIGHT),
	float2(.75 / BUFFER_WIDTH, -.433012 / BUFFER_HEIGHT),
	float2(.5 / BUFFER_WIDTH, 0. / BUFFER_HEIGHT),
	float2(.25 / BUFFER_WIDTH, .433012 / BUFFER_HEIGHT),
	float2(-.25 / BUFFER_WIDTH, .433012 / BUFFER_HEIGHT),
	float2(-.5 / BUFFER_WIDTH, 0. / BUFFER_HEIGHT),
	float2(-.25 / BUFFER_WIDTH, -.433012 / BUFFER_HEIGHT),
	float2(.25 / BUFFER_WIDTH, -.433012 / BUFFER_HEIGHT),

	// Low Quality Hexagon
	float2(0., 0.),
	float2(1. / BUFFER_WIDTH, 0. / BUFFER_HEIGHT),
	float2(.5 / BUFFER_WIDTH, .866025 / BUFFER_HEIGHT),
	float2(-.5 / BUFFER_WIDTH, .866025 / BUFFER_HEIGHT),
	float2(-1. / BUFFER_WIDTH, 0. / BUFFER_HEIGHT),
	float2(-.5 / BUFFER_WIDTH, -.866025 / BUFFER_HEIGHT),
	float2(.5 / BUFFER_WIDTH, -.866025 / BUFFER_HEIGHT),
	float2(.5 / BUFFER_WIDTH, .288675 / BUFFER_HEIGHT),
	float2(0. / BUFFER_WIDTH, .577350 / BUFFER_HEIGHT),
	float2(-.5 / BUFFER_WIDTH, .288675 / BUFFER_HEIGHT),
	float2(-.5 / BUFFER_WIDTH, -.288675 / BUFFER_HEIGHT),
	float2(0. / BUFFER_WIDTH, -.577350 / BUFFER_HEIGHT),
	float2(.5 / BUFFER_WIDTH, -.288675 / BUFFER_HEIGHT),

	// Artsy
	float2(0. / BUFFER_WIDTH, 0. / BUFFER_HEIGHT),
	float2(1. / BUFFER_WIDTH, 0. / BUFFER_HEIGHT),
	float2(-1. / BUFFER_WIDTH, 0. / BUFFER_HEIGHT),
	float2(0. / BUFFER_WIDTH, 1. / BUFFER_HEIGHT),
	float2(0. / BUFFER_WIDTH, -1. / BUFFER_HEIGHT),
	float2(1. / BUFFER_WIDTH, 1. / BUFFER_HEIGHT),
	float2(-1. / BUFFER_WIDTH, -1. / BUFFER_HEIGHT),
};

// kernelOffsets stores the starting index of each kernel, and kernelLengths stores the ending index + 1 for each kernel
static const int kernelOffsets[10] = { 0, 43, 65, 81, 130, 155, 168, 205, 224, 237 };
static const int kernelLengths[10] = { 43, 65, 81, 130, 155, 168, 205, 224, 237, 244 };

// The kernel used for the depth check in auto focus
static const int depthCheckKernel = 0;

// Threasholds for dilation
static const float dilateMinThreshold = 0.1;
static const float dilateMaxThreshold = 0.3;


// Calculates the focus, and applies smothing if using auto focus
float CalcFocus_PS(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target{

	float focusTo;
	float focusFrom = tex2D(focusTexPrevSampler, float2(0.0, 0.0)).x;

	if (autoFocus) {
		if (mouseFocus) {
			return ReShade::GetLinearizedDepth(mouse_point / float2(BUFFER_WIDTH, BUFFER_HEIGHT));
		}
		else {
			focusTo = 1.0;
			for (int i = kernelOffsets[depthCheckKernel]; i < kernelLengths[depthCheckKernel]; i++) {
				float depth = ReShade::GetLinearizedDepth(focusPoint + kernel[i] * focusPointSize);
				focusTo = min(focusTo, depth);
			}
			if (focusTo == focusFrom)
				return focusTo;

			float change = (focusTo - focusFrom) / abs(focusTo - focusFrom);
			change *= (abs(focusTo - focusFrom) > frametime / focusSpeed) ? (frametime / focusSpeed) : abs(focusTo - focusFrom);

			return clamp(focusFrom + change, 0.0, 1.0);
		}
	}
	else
		return focusDist;
}

// Copy the focus information for the current frame into the buffer for the next frame
float CopyFocus_PS(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target{
	return tex2D(focusTexSampler, texcoord.xy).x;
}

// Vertex shader for CoC, reads focus information and performs menu check (disables blur during full screen menu)
void DOF_VS(in uint id : SV_VertexID, out float4 position : SV_Position, out float2 texcoord : TEXCOORD, out float dist: MIN_DEPTH, nointerpolation out bool menu : MENU)
{
	float menuCheck = ReShade::GetLinearizedDepth(float2(0, 0)) * ReShade::GetLinearizedDepth(float2(1, 0)) * ReShade::GetLinearizedDepth(float2(0, 1)) * ReShade::GetLinearizedDepth(float2(1, 1));
	menu = menuCheck == 0.0 || menuCheck == 1.0;

	dist = tex2Dfetch(focusTexSampler, float2(0.0, 0.0)).x;

	texcoord.x = (id == 2) ? 2.0 : 0.0;
	texcoord.y = (id == 1) ? 2.0 : 0.0;
	position = float4(texcoord * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}

// Pixel shader for CoC, calculates CoC and stores to cocBuffer
float Calc_CoC_PS(in float4 position : SV_Position, in float2 texcoord : TexCoord, in float dist : MIN_DEPTH, nointerpolation in bool menu : MENU) : SV_Target
{
	if (menu)
		return 0.0;

	float depth = ReShade::GetLinearizedDepth(texcoord);

	float coc = (depth - dist) * blurMult;
	if (disableNear) {
		coc = max(0.0, coc);
	}
	else {
		coc = abs(coc);
	}

	return coc;
}

// Blur pixel shader, applies blur to final image, reads CoC value from cocBuffer
float3 BlurEffect_PS(in float4 position : SV_Position, in float2 texcoord : TexCoord) : SV_Target
{
	float size = tex2Dfetch(cocSampler, position.xy).r;

	if (size == 0.0)
		discard;

	float3 col = float3(0., 0., 0.);
	float weight = 0.0;

	for (int i = kernelOffsets[blurType]; i < kernelLengths[blurType]; i++) {
		float2 pos = position.xy + kernel[i] * size * ReShade::ScreenSize;
		float cocWeight = tex2Dfetch(cocSampler, pos).r;
		weight += cocWeight;
		col += tex2Dfetch(ReShade::BackBuffer, pos).rgb * cocWeight;
	}

	col /= weight;

	if (showFocusArea && abs(length((texcoord - focusPoint) * float2(BUFFER_WIDTH, BUFFER_HEIGHT))) <= focusPointSize)
		col *= float3(4.0, 4.0, 4.0);

    return	col;
}

// Dilation pixel shader, applies dilation to final image, reads CoC value from cocBuffer
float3 DilateEffect_PS(in float4 position : SV_Position, in float2 texcoord : TexCoord) : SV_Target
{
	float size = tex2Dfetch(cocSampler, position.xy).r;

	if (size == 0.0)
		discard;

	float maxVal = 0.0;
	float3 maxCol;

	for (int i = kernelOffsets[blurType]; i < kernelLengths[blurType]; i++) {
		float coc = tex2Dfetch(cocSampler, position.xy + kernel[i] * size * ReShade::ScreenSize).r;
		if (coc >= size) {
			float3 col = tex2Dfetch(ReShade::BackBuffer, position.xy + kernel[i] * size * ReShade::ScreenSize).rgb;
			float val = dot(col, float3(0.21, 0.72, 0.07));
			if (val > maxVal) {
				maxVal = val;
				maxCol = col;
			}
		}
	}

	if (showFocusArea && abs(length((position.xy - focusPoint) * float2(BUFFER_WIDTH, BUFFER_HEIGHT))) <= focusPointSize)
		maxCol *= float3(4.0, 4.0, 4.0);

	return lerp(tex2Dfetch(ReShade::BackBuffer, position.xy).rgb, maxCol, smoothstep(dilateMinThreshold, dilateMaxThreshold, maxVal));
}

technique DOF < ui_tooltip = "DOF which blurs the background or foreground while keeping the character in focus."; >
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = CalcFocus_PS;
		RenderTarget = focusTex;
	}
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = CopyFocus_PS;
		RenderTarget = focusTexPrev;
	}
	pass
	{
		VertexShader = DOF_VS;
		PixelShader = Calc_CoC_PS;
		RenderTarget = cocBuffer;
	}
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = BlurEffect_PS;
	}
}

technique DOF_Paint < ui_tooltip = "DOF but uses a dilation effect to make the scene look like it is \"painted\"."; >
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = CalcFocus_PS;
		RenderTarget = focusTex;
	}
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = CopyFocus_PS;
		RenderTarget = focusTexPrev;
	}
	pass
	{
		VertexShader = DOF_VS;
		PixelShader = Calc_CoC_PS;
		RenderTarget = cocBuffer;
	}
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = DilateEffect_PS;
	}
}