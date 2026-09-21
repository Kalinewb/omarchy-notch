#version 440

// Another plugin's panel, drawn on the notch with the hue taken out.
//
// A hosted panel is the one thing in the notch the notch cannot hand its
// colours to: it asks Omarchy's `Color` and `Style` singletons itself, so a
// theme's accent -- or a plugin's own hard-coded blue -- paints its selected
// rows, its toggle buttons and its graphs while it sits on the notch's black.
// DESIGN-PHILOSOPHY.md's rule is that nothing on the notch has a hue and that
// selected differs from normal by alpha; this is that rule applied to a guest
// that never heard it.
//
// Lightness, not luminance. Rec. 709 luminance weights blue at 0.07, so a
// saturated blue would come out nearly black and a selected row would vanish
// into the notch instead of reading as selected. HSL lightness -- halfway
// between the brightest and dimmest channel -- keeps a colour's presence: pure
// blue and pure red both land at mid grey, white stays white, and anything
// already grey is unchanged.
//
// The texture is premultiplied, so it is divided out before the channels are
// compared and put back afterwards: a 20 %-alpha fill must desaturate by its
// own colour, not by the black it is lying on.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
};

layout(binding = 1) uniform sampler2D source;

void main() {
    vec4 c = texture(source, qt_TexCoord0);
    vec3 rgb = c.a > 0.0 ? c.rgb / c.a : c.rgb;
    float lightness = (max(max(rgb.r, rgb.g), rgb.b) + min(min(rgb.r, rgb.g), rgb.b)) * 0.5;
    fragColor = vec4(vec3(lightness) * c.a, c.a) * qt_Opacity;
}
