require( "ggbuild.gen_ninja" )
require( "ggbuild.git_version" )

global_cxxflags( "-I source -I libs" )

msvc_global_cxxflags( "/std:c++17 /W4 /wd4100 /wd4146 /wd4189 /wd4201 /wd4307 /wd4324 /wd4351 /wd4127 /wd4505 /wd4530 /wd4702 /wd4706 /D_CRT_SECURE_NO_WARNINGS" )
msvc_global_cxxflags( "/wd4244 /wd4267" ) -- silence conversion warnings because there are tons of them
msvc_global_cxxflags( "/wd4611" ) -- setjmp warning
msvc_global_cxxflags( "/GR- /EHs-c-" )

gcc_global_cxxflags( "-std=c++17 -msse4.2 -mpopcnt -fno-exceptions -fno-rtti -fno-strict-aliasing -fno-strict-overflow -fno-math-errno -fvisibility=hidden" )
gcc_global_cxxflags( "-Wall -Wextra -Wcast-align -Wvla -Wformat-security -Wimplicit-fallthrough" ) -- -Wconversion
gcc_global_cxxflags( "-Wno-unused-parameter -Wno-missing-field-initializers" )

if config == "release" then
	global_cxxflags( "-DPUBLIC_BUILD" )
	gcc_global_cxxflags( "-Werror" ) -- -Werror in dev is too annoying. TODO: make a whitelist instead
	gcc_global_cxxflags( "-Wno-error=switch -Wno-error=sign-compare -Wno-error=dynamic-class-memaccess" ) -- these are difficult to fix
else
	global_cxxflags( "-DTRACY_ENABLE" )
end

require( "libs.cgltf" )
require( "libs.curl" )
require( "libs.discord" )
require( "libs.freetype" )
require( "libs.gg" )
require( "libs.glad" )
require( "libs.glfw3" )
require( "libs.imgui" )
require( "libs.jsmn" )
require( "libs.luau" )
require( "libs.mbedtls" )
require( "libs.meshoptimizer" )
require( "libs.monocypher" )
require( "libs.openal" )
require( "libs.picohttpparser" )
require( "libs.rgbcx" )
require( "libs.stb" )
require( "libs.tracy" )
require( "libs.yoga" )
require( "libs.zstd" )

require( "source.tools.bc4" )
require( "source.tools.dieselmap" )

do
	local platform_libs = OS == "windows" and { } or { "mbedtls" }

	bin( "client", {
		srcs = {
			"source/cgame/*.cpp",
			"source/client/**.cpp",
			"source/game/**.cpp",
			"source/gameshared/*.cpp",
			"source/qcommon/**.cpp",
			"source/server/sv_*.cpp",
		},

		libs = {
			"imgui",

			"cgltf",
			"curl",
			"discord",
			"freetype",
			"ggentropy",
			"ggformat",
			"ggtime",
			"glad",
			"glfw3",
			"jsmn",
			"luau",
			"monocypher",
			"openal",
			"picohttpparser",
			"stb_image",
			"stb_image_write",
			"stb_rect_pack",
			"stb_vorbis",
			"tracy",
			"yoga",
			"zstd",
			platform_libs,
		},

		rc = "source/client/platform/client",

		windows_ldflags = "shell32.lib gdi32.lib ole32.lib oleaut32.lib ws2_32.lib crypt32.lib winmm.lib version.lib imm32.lib advapi32.lib /SUBSYSTEM:WINDOWS",
		linux_ldflags = "-lm -lpthread -ldl",
		no_static_link = true,
	} )
end

do
	bin( "server", {
		srcs = {
			"source/game/**.cpp",
			"source/gameshared/*.cpp",
			"source/qcommon/**.cpp",
			"source/server/**.cpp",
		},

		libs = {
			"ggentropy",
			"ggformat",
			"ggtime",
			"monocypher",
			"picohttpparser",
			"tracy",
			"zstd",
		},

		windows_ldflags = "ole32.lib ws2_32.lib crypt32.lib shell32.lib user32.lib advapi32.lib",
		linux_ldflags = "-lm -lpthread",
	} )
end

write_ninja_script()
