// VANDAL parallax-occlusion material shader.
// Tuned for visible depth on 64x64 retro textures without excessive edge swim.

mat3 VandalGetTBN()
{
    vec3 n = normalize(vWorldNormal.xyz);
    vec3 p = pixelpos.xyz;
    vec2 uv = vTexCoord.st;

    vec3 dp1 = dFdx(p);
    vec3 dp2 = dFdy(p);
    vec2 duv1 = dFdx(uv);
    vec2 duv2 = dFdy(uv);

    vec3 dp2perp = cross(n, dp2);
    vec3 dp1perp = cross(dp1, n);
    vec3 t = dp2perp * duv1.x + dp1perp * duv2.x;
    vec3 b = dp2perp * duv1.y + dp1perp * duv2.y;
    float invmax = inversesqrt(max(max(dot(t, t), dot(b, b)), 0.000001));
    return mat3(t * invmax, b * invmax, n);
}

vec2 VandalParallaxUV(mat3 tbn)
{
    const float depthScale = 0.075;
    const float minLayers = 12.0;
    const float maxLayers = 28.0;

    vec3 viewDir = normalize(transpose(tbn) * (uCameraPos.xyz - pixelpos.xyz));
    float vz = max(abs(viewDir.z), 0.20);
    float layerCount = mix(maxLayers, minLayers, clamp(vz, 0.0, 1.0));
    float layerStep = 1.0 / layerCount;
    vec2 uvStep = (viewDir.xy / vz) * depthScale / layerCount;

    vec2 uv = vTexCoord.st;
    float layerDepth = 0.0;

    // Inverted depth convention: white is raised, black is recessed.
    float mapDepth = 1.0 - texture(tex_heightmap, uv).r;

    for (int i = 0; i < 28; ++i)
    {
        if (layerDepth >= mapDepth) break;
        uv -= uvStep;
        layerDepth += layerStep;
        mapDepth = 1.0 - texture(tex_heightmap, uv).r;
    }

    vec2 previousUV = uv + uvStep;
    float afterDepth = mapDepth - layerDepth;
    float beforeDepth = (1.0 - texture(tex_heightmap, previousUV).r) - layerDepth + layerStep;
    float denominator = afterDepth - beforeDepth;
    float weight = abs(denominator) > 0.00001 ? clamp(afterDepth / denominator, 0.0, 1.0) : 0.0;

    return mix(uv, previousUV, weight);
}

vec3 VandalNormal(mat3 tbn, vec2 uv)
{
#if defined(NORMALMAP)
    vec3 mapNormal = texture(normaltexture, uv).xyz;
    mapNormal = mapNormal * (255.0 / 127.0) - (128.0 / 127.0);
    mapNormal.y = -mapNormal.y;
    return normalize(tbn * mapNormal);
#else
    return normalize(vWorldNormal.xyz);
#endif
}

void SetupMaterial(inout Material material)
{
    mat3 tbn = VandalGetTBN();
    vec2 uv = VandalParallaxUV(tbn);

    // Base + normal
    material.Base = getTexel(uv);
    material.Normal = VandalNormal(tbn, uv);

    // --- BRIGHTMAP SUPPORT (FULLY FIXED) ---
#if defined(BRIGHTMAP)
    vec4 bm = texture(brighttexture, uv);

    // Additive emissive contribution (classic brightmap behavior)
    material.Base.rgb += bm.rgb;

    // Optional true emissive output (uncomment if desired)
    // material.Emissive = bm.rgb;
#endif
    // ---------------------------------------

#if defined(SPECULAR)
    material.Specular = texture(speculartexture, uv).rgb;
    material.Glossiness = uSpecularMaterial.x;
    material.SpecularLevel = uSpecularMaterial.y;
#endif

#if defined(PBR)
    material.Metallic = texture(metallictexture, uv).r;
    material.Roughness = texture(roughnesstexture, uv).r;
    material.AO = texture(aotexture, uv).r;
#endif
}