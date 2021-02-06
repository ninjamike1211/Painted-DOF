# Painted-DOF
A Depth of Field shader for reshade which can run in bokeh or "painted" mode.

To install, simple download DOF_Paint.fx into reshade-shaders/Shaders. Inside reshade, unable "DOF" or "DOF_Paint" for the effect.

In reshade, this shader supplies two tequniques, "DOF", and "DOF_Paint". "DOF" creates a more realistic bokeh-like background blur, while "DOF_Paint" creates a more paint-like artistic look. Both effects can be layered, creating some interesting visuals.

The "DOF" shader uses a poisson kernel to sample surrounding pixels, creating a bokeh blur. The user can change the specific kernel, either to tweak performance/quality, or to change to shape. Included by default are three shapes (circle, diamond, and hexagon) with three quality presets each, along with a "painted" kernel intended to look like paint strokes. This kernel works best in the "painted" mode.

When using the "DOF_Paint" in reshade, the shader acts identical to "DOF", using the exact same settings, except for the manner in which it generates blur. Instead of using an average type blur like the bokeh effect, this mode uses a dilation effect where the shader takes the maximum value pixel in it's sample range. This generates a paint-like effect.

Both shaders can utilize manual or auto-focus. Manual focus allows the user to set the focus point to any point from 0 (foreground) to 1 (background). Autofocus uses a high quality circle poisson kernel to sample the depth buffer of a given area, and then focuses on the closest object in this area. The position and size of this area can be configured and made visable on screen. This is intended so that instead of sampling a single point for the auto-focus depth, it samples an area. If a character is moving around on screen, they might not always be in the center of the screen, they might drift around the screen a little as the camera moves. This area is intedned to still focus on the player despite this. The Focus speed value allows the user to adjust the speed at which the shader will transition between different focus values. The value represents the number of milliseconds it takes to transition from a focus of 0 (complete foreground) to a focus of 1 (complete background) or vise versa. Additionally, the shader supports focusing on the mouse position (only when auto-focus is enabled).
