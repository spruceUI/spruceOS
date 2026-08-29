
#define lerp mix

float uv_clip_mask(vec2 uv)
{
	float flx = (uv.x < 0.0f) ? 0.0f : 1.0f;
	float fgx = (uv.x > 1.0f) ? 0.0f : 1.0f;
	float fx = min(flx, fgx);
	float fly = (uv.y < 0.0f) ? 0.0f : 1.0f;
	float fgy = (uv.y > 1.0f) ? 0.0f : 1.0f;
	float fy = min(fly, fgy);
	return min(fx, fy);
}
