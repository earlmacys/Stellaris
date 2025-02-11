Includes = 
{
	"constants.fxh"
	"terra_incognita.fxh"
}

PixelShader =
{
	Samplers =
	{
		Diffuse = {
			Index = 0;
			MagFilter = "Linear";
			MinFilter = "Linear";
			AddressU = "Wrap";
			AddressV = "Wrap";
		}
		BorderID = {
			Index = 1;
			MagFilter = "point";
			MinFilter = "point";
			MipFilter = "none";
			AddressU = "Clamp";
			AddressV = "Clamp";
		}
		BorderSDF = {
			Index = 2;
			MagFilter = "linear";
			MinFilter = "linear";
			AddressU = "Clamp";
			AddressV = "Clamp";
		}
		TerraIncognitaTexture = 
		{
			Index = 3;
			MagFilter = "Linear";
			MinFilter = "Linear";
			AddressU = "Clamp";
			AddressV = "Clamp";
		}
	}
}

VertexStruct VS_INPUT
{
	float2  vPosition 	: POSITION;
	float2  vUV 		: TEXCOORD0;
};

VertexStruct VS_INPUT_STAR_PIN
{
	float2	vOffset		: POSITION;
	float	vGroundStarBlend : TEXCOORD0;
};

VertexStruct VS_OUTPUT_STAR_PIN
{
	float4 vPosition	: PDX_POSITION;
	float3 vPos			: TEXCOORD0;
};

VertexStruct VS_OUTPUT
{
    float4 vPosition 	: PDX_POSITION;
	float2 vUV			: TEXCOORD0;
	float2 vPos			: TEXCOORD2;
};

VertexStruct VS_INPUT_SECTOR
{
	float2	vPosition	: POSITION;
	float	vDistance	: TEXCOORD0;
};

VertexStruct VS_OUTPUT_SECTOR
{
	float4 	vPosition 	: PDX_POSITION;
	float2 	vUV			: TEXCOORD0;
	float 	vDistance	: TEXCOORD1;
};

ConstantBuffer( CountryBorders, 0, 0 )	#Country borders
{
	float4x4	ViewProjectionMatrix;
	float3		vCamPos;
	float3		vCamLookAtDir;
	float3		vCamUpDir;
	float3		vCamRightDir;
	float2		vCamFOV;
	float 		vFade;
	float		vTextureSize;
};

ConstantBuffer( StarPins, 0, 0 )	#Star pins
{
	float4x4	ViewProjectionMatrix;
	float3		StarPos;
	float3		GroundPos;
	float4		vStarPinColor;
};

ConstantBuffer( SectorBorders, 0, 0 )	#Sector borders
{
	float4x4	ViewProjectionMatrix;
	float3	vCamPos;
	float	vCamZoom;
	float2	vBoundsMin;
	float2	vBoundsMax;
}

ConstantBuffer( CountrySdfBorders, 0, 0 ) #SDF borders
{
	float4x4	ViewProjectionMatrix;
	float3		vCamPos;
	float4		PrimaryColor;
	float4		SecondaryColor;
	float		vSdfTime;
	float		vBorderHighLight;
}

VertexShader =
{
	MainCode VertexShader
		ConstantBuffers = { CountryBorders }
	[[
		VS_OUTPUT main(const VS_INPUT v )
		{
			VS_OUTPUT Out;
			// Agami’s mod: raise borders slightly (y = 1.0f)
			Out.vPosition  	= mul( ViewProjectionMatrix, float4( v.vPosition.x, 1.0f, v.vPosition.y, 1.0f ) );
			Out.vUV			= v.vUV;
			Out.vPos 		= v.vPosition.xy;
			return Out;
		}
	]]
	MainCode VertexShaderStarPin
		ConstantBuffers = { StarPins }
	[[
		VS_OUTPUT_STAR_PIN main( const VS_INPUT_STAR_PIN v )
		{
			VS_OUTPUT_STAR_PIN Out;
			float3 vPos = lerp( GroundPos, StarPos, v.vGroundStarBlend );
			vPos.xz += v.vOffset;
			
			Out.vPosition  	= mul( ViewProjectionMatrix, float4( vPos, 1.0f ) );
			Out.vPos = vPos;
			return Out;
		}
	]]
	MainCode VertexShaderSectorSdf
		ConstantBuffers = { SectorBorders }
	[[
		VS_OUTPUT_SECTOR main(const VS_INPUT_SECTOR v )
		{
			VS_OUTPUT_SECTOR Out;
			Out.vPosition  	= mul( ViewProjectionMatrix, float4( v.vPosition.x, 0.0f, v.vPosition.y, 1.0f ) );
			Out.vUV 		= ( v.vPosition - vBoundsMin ) / ( vBoundsMax - vBoundsMin );
			Out.vDistance	= v.vDistance;
			return Out;
		}
	]]
}

PixelShader =
{
	MainCode PixelShaderSDF
		ConstantBuffers = { CountrySdfBorders }
	[[
		float4 main( VS_OUTPUT v ) : PDX_COLOR
		{
			// SDF alpha
			float vDist = tex2D( BorderSDF, v.vUV ).a;

			// Standard discard for anything beyond the "max" region
			const float vMaxMidDistance = 0.53f;
			const float vMinMidDistance = 0.47f;
			clip( vMaxMidDistance - vDist );
			
			// Distance‐based scaling
			float vCameraDistance = length( vCamPos - float3( v.vPos.x, 0.f, v.vPos.y ) );
			float vCamDistFactor  = saturate( vCameraDistance / 1600.0f );
			
			// SDF midpoint shifts from 0.47 -> 0.53
			float vMid = lerp( vMinMidDistance, vMaxMidDistance, vCamDistFactor );
			
			// Epsilon smoothing
			float vEpsilon = 0.005f + vCamDistFactor * 0.005f;
			float vOffset  = 0.0f;
			float vAlpha   = smoothstep( vMid + vEpsilon, vMid - vEpsilon, vDist + vOffset );

			// -------------------------------------------
			// Minimizing the interior "fill":
			//  1) Lower vAlphaMin
			//  2) Scale down vAlphaFill
			// -------------------------------------------
			float vAlphaMin = 0.0f; // was 0.1f + 0.5f * vCamDistFactor
								
			// Original equation: saturate( vMid + (vDist - 0.8f + vEdgeWidth*8.0f)*2.0f ) * 0.6f
			// We'll scale it down to reduce interior color drastically:
			float fillRaw   = saturate( vMid + (vDist - 0.8f + (0.025f + (0.35f * vCamDistFactor / 3.5f))*8.0f ) * 2.0f );
			float vAlphaFill = max( vAlphaMin, fillRaw * 0.1f ); // 0.1f = 1/6 original

			// Thicken or lighten the edge
			float vEdgeWidth     = 0.025f + (0.35f * vCamDistFactor / 3.5f);
			const float vEdgeSharpness = 100.0f;

			// Black edging
			float vBlackBorderWidth       = vEdgeWidth * 0.25f;
			const float vBlackBorderSharp = 25.0f;

			float vAlphaOuterEdge = smoothstep( vMid + vEpsilon, vMid - vEpsilon, vDist + vOffset );
			float vAlphaEdge      = saturate( (vDist - vMid + vEdgeWidth) * vEdgeSharpness );

			// Lighten primary color
			float4 lightenPrimary = clamp(
				PrimaryColor, 
				float4(0.2, 0.2, 0.2, 1.0), 
				float4(0.9, 0.9, 0.9, 1.0)
			) * 1.9f;

			// Blend primary & secondary color
			float4 vColor = vAlphaEdge * lightenPrimary + (1 - vAlphaEdge) * SecondaryColor;

			// Add black edging fade
			vColor *= 1.0f - (0.25f * saturate( (vDist - vMid + vBlackBorderWidth) * vBlackBorderSharp ));

			// Final alpha: combine edge + scaled-down fill
			vColor.a = saturate( vAlphaEdge + vAlphaFill ) * vAlphaOuterEdge;

			// Terra Incognita fade
			float2 vTIUV = ( v.vPos.xy + GALAXY_SIZE * 0.5f ) / GALAXY_SIZE;
			vColor.a *= tex2D( TerraIncognitaTexture, vTIUV ).a;

			return vColor;
		}
	]]
		
	MainCode PixelShaderCentroid
		ConstantBuffers = { CountryBorders }
	[[
		float4 main( VS_OUTPUT v ) : PDX_COLOR
		{
			float4 vColor = tex2D( Diffuse, float2( -v.vUV.x, v.vUV.y ) );
			vColor.a *= vFade * 0.65f;
			return vColor;
		}
	]]
	MainCode PixelShaderStarPin
		ConstantBuffers = { StarPins }
	[[
		float4 main( VS_OUTPUT_STAR_PIN v ) : PDX_COLOR
		{
			float4 vColor = vStarPinColor;
			vColor.a = 0.0f;
			
			vColor = ApplyTerraIncognita( vColor, v.vPos.xz, 4.f, TerraIncognitaTexture );
			
			return saturate( vColor );
		}
	]]
	MainCode PixelShaderSectorSdf
		ConstantBuffers = { SectorBorders }
	[[
		float4 main( VS_OUTPUT_SECTOR v ) : PDX_COLOR
		{
			float vDist = tex2D( BorderSDF, v.vUV ).a;
			float vDistance = min( v.vDistance / 64.0f, 0.5f - vDist );
			clip( vDistance - 0.0001f );
					
			float vThickness     = 0.005f + ( vCamZoom / 70000.f ) / 3.0f;
			float vInvThickness = 1.f / vThickness;

			float vValue = 1.f - pow( (vDistance - vThickness) * vInvThickness, 2.f );
			if( v.vDistance > vThickness )
			{
				vValue = max( vValue, 0.1f );
			}
			vValue = saturate( vValue );

			float3 vColor = float3( 1.f, 1.f, 1.f );
			return float4( vColor * vValue, vValue * 0.75f + 0.3f );
		}
	]]
}

BlendState BlendState
{
	BlendEnable = yes
	AlphaTest   = no
	SourceBlend = "SRC_ALPHA"
	DestBlend   = "INV_SRC_ALPHA"
	WriteMask   = "RED|GREEN|BLUE|ALPHA"
}

BlendState BlendStateAdditiveBlend
{
	BlendEnable = yes
	SourceBlend = "SRC_ALPHA"
	DestBlend   = "ONE"
	WriteMask   = "RED|GREEN|BLUE|ALPHA"
}

DepthStencilState DepthStencilState
{
	DepthEnable    = no
	DepthWriteMask = "depth_write_zero"
}

RasterizerState RasterizerState
{
	FillMode  = "FILL_SOLID"
	CullMode  = "CULL_NONE"
	FrontCCW  = no
	#FillMode = "fill_wireframe"
}

Effect BorderSDF
{
	VertexShader = "VertexShader"
	PixelShader  = "PixelShaderSDF"
}

Effect BorderCentroid
{
	VertexShader = "VertexShader"
	PixelShader  = "PixelShaderCentroid"
}

Effect StarPin
{
	VertexShader = "VertexShaderStarPin"
	PixelShader  = "PixelShaderStarPin"
	
	BlendState = "BlendStateAdditiveBlend"
}

Effect SectorSdf
{
	VertexShader = "VertexShaderSectorSdf"
	PixelShader  = "PixelShaderSectorSdf"
	
	BlendState = "BlendStateAdditiveBlend"
}
