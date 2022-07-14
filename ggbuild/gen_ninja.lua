package.path = ( "./?.lua;./?/make.lua" ):gsub( "/", package.config:sub( 1, 1 ) )

local lfs = require( "INTERNAL_LFS" )

local configs = { }

configs[ "windows" ] = {
	bin_suffix = ".exe",
	obj_suffix = ".obj",
	lib_suffix = ".lib",
	dll_suffix = ".dll",

	toolchain = "msvc",

	cxxflags = "/c /Oi /Gm- /nologo",
	ldflags = "user32.lib shell32.lib advapi32.lib dbghelp.lib /NOLOGO",
}

configs[ "windows-debug" ] = {
	cxxflags = "/MTd /Z7 /FC",
	ldflags = "/DEBUG /DEBUG:FULL /FUNCTIONPADMIN /OPT:NOREF /OPT:NOICF",
}
configs[ "windows-release" ] = {
	cxxflags = "/O2 /MT /DNDEBUG",
	output_dir = "release/",
}
configs[ "windows-bench" ] = {
	bin_suffix = "-bench.exe",
	cxxflags = configs[ "windows-release" ].cxxflags,
	ldflags = configs[ "windows-release" ].ldflags,
	prebuilt_lib_dir = "windows-release",
}

configs[ "linux" ] = {
	obj_suffix = ".o",
	lib_prefix = "lib",
	lib_suffix = ".a",
	dll_suffix = ".so",

	toolchain = "gcc",
	cxx = "g++",
	ar = "ar",

	cxxflags = "-c -g -fdiagnostics-color",
	ldflags = "-fuse-ld=gold -no-pie",
}

configs[ "linux-debug" ] = {
	cxxflags = "-fno-omit-frame-pointer",
}
configs[ "linux-asan" ] = {
	bin_suffix = "-asan",
	cxxflags = configs[ "linux-debug" ].cxxflags .. " -fsanitize=address",
	ldflags = "-fsanitize=address -static-libasan",
	prebuilt_lib_dir = "linux-debug",
}
configs[ "linux-tsan" ] = {
	bin_suffix = "-tsan",
	cxxflags = configs[ "linux-debug" ].cxxflags .. " -fsanitize=thread",
	ldflags = "-fsanitize=thread -static-libtsan",
	prebuilt_lib_dir = "linux-debug",
}
configs[ "linux-release" ] = {
	cxx = "ggbuild/zig/zig c++",
	ar = "ggbuild/zig/zig ar",

	cxxflags = "-O2 -DNDEBUG",
	ldflags = "",
	output_dir = "release/",
}
configs[ "linux-bench" ] = {
	bin_suffix = "-bench",
	cxxflags = configs[ "linux-release" ].cxxflags,
	ldflags = configs[ "linux-release" ].ldflags,
	prebuilt_lib_dir = "linux-release",
}

local function identify_host()
	local dll_ext = package.cpath:match( "(%a+)$" )

	if dll_ext == "dll" then
		return "windows"
	end

	local p = assert( io.popen( "uname -s" ) )
	local uname = assert( p:read( "*all" ) ):gsub( "%s*$", "" )
	assert( p:close() )

	if uname == "Linux" then
		return "linux"
	end

	io.stderr:write( "can't identify host OS" )
	os.exit( 1 )
end

OS = identify_host()
config = arg[ 1 ] or "debug"

local OS_config = OS .. "-" .. config

if not configs[ OS_config ] then
	io.stderr:write( "bad config: " .. OS_config .. "\n" )
	os.exit( 1 )
end

local function concat( key )
	return ""
		.. ( ( configs[ OS ] and configs[ OS ][ key ] ) or "" )
		.. " "
		.. ( ( configs[ OS_config ] and configs[ OS_config ][ key ] ) or "" )
end

local function rightmost( key )
	return nil
		or ( configs[ OS_config ] and configs[ OS_config ][ key ] )
		or ( configs[ OS ] and configs[ OS ][ key ] )
		or ""
end

local output_dir = rightmost( "output_dir" )
local bin_suffix = rightmost( "bin_suffix" )
local obj_suffix = rightmost( "obj_suffix" )
local lib_prefix = rightmost( "lib_prefix" )
local lib_suffix = rightmost( "lib_suffix" )
local dll_suffix = rightmost( "dll_suffix" )
local prebuilt_lib_dir = rightmost( "prebuilt_lib_dir" )
prebuilt_lib_dir = prebuilt_lib_dir == "" and OS_config or prebuilt_lib_dir
local cxxflags = concat( "cxxflags" )
local ldflags = rightmost( "ldflags" )

toolchain = rightmost( "toolchain" )

local dir = "build/" .. OS_config
local output = { }

local objs = { }
local objs_flags = { }
local objs_extra_flags = { }

local bins = { }
local bins_flags = { }
local bins_extra_flags = { }

local libs = { }
local prebuilt_libs = { }
local prebuilt_dlls = { }

local function flatten_into( res, t )
	for _, x in ipairs( t ) do
		if type( x ) == "table" then
			flatten_into( res, x )
		else
			table.insert( res, x )
		end
	end
end

local function flatten( t )
	local res = { }
	flatten_into( res, t )
	return res
end

local function join_srcs( names, suffix )
	if not names then
		return ""
	end

	local flat = flatten( names )
	for i = 1, #flat do
		flat[ i ] = dir .. "/" .. flat[ i ] .. suffix
	end
	return table.concat( flat, " " )
end

local function join_libs( names )
	local joined = { }
	local dlls = { }
	for _, lib in ipairs( flatten( names ) ) do
		local prebuilt_lib = prebuilt_libs[ lib ]
		local prebuilt_dll = prebuilt_dlls[ lib ]

		if prebuilt_lib then
			for _, archive in ipairs( prebuilt_lib ) do
				table.insert( joined, "libs/" .. lib .. "/" .. prebuilt_lib_dir .. "/" .. lib_prefix .. archive .. lib_suffix )
			end
		elseif prebuilt_dll then
			table.insert( dlls, output_dir .. prebuilt_dll .. dll_suffix )
		else
			table.insert( joined, dir .. "/" .. lib_prefix .. lib .. lib_suffix )
		end
	end

	return table.concat( joined, " " ) .. " | " .. table.concat( dlls )
end

local function printf( form, ... )
	print( form and form:format( ... ) or "" )
end

local function glob_impl( dir, rel, res, prefix, suffix, recursive )
	for filename in lfs.dir( dir .. rel ) do
		if filename ~= "." and filename ~= ".." then
			local fullpath = dir .. rel .. "/" .. filename
			local attr = lfs.attributes( fullpath )

			if attr.mode == "directory" then
				if recursive then
					glob_impl( dir, rel .. "/" .. filename, res, prefix, suffix, true )
				end
			else
				local prefix_start = dir:len() + rel:len() + 2
				if fullpath:find( prefix, prefix_start, true ) == prefix_start and fullpath:sub( -suffix:len() ) == suffix then
					table.insert( res, fullpath )
				end
			end
		end
	end
end

local function glob( srcs )
	local res = { }
	for _, pattern in ipairs( flatten( srcs ) ) do
		if pattern:find( "*", 1, true ) then
			local dir, prefix, suffix = pattern:match( "^(.-)/?([^/*]*)%*+(.*)$" )
			local recursive = pattern:find( "**", 1, true ) ~= nil
			assert( not recursive or prefix == "" )

			glob_impl( dir, "", res, prefix, suffix, recursive )
		else
			table.insert( res, pattern )
		end
	end
	return res
end

local function add_srcs( srcs )
	for _, src in ipairs( srcs ) do
		if not objs[ src ] then
			objs[ src ] = { }
		end
	end
end

function bin( bin_name, cfg )
	assert( type( cfg ) == "table", "cfg should be a table" )
	assert( type( cfg.srcs ) == "table", "cfg.srcs should be a table" )
	assert( not cfg.libs or type( cfg.libs ) == "table", "cfg.libs should be a table or nil" )
	assert( not bins[ bin_name ] )

	bins[ bin_name ] = cfg
	cfg.srcs = glob( cfg.srcs )
	add_srcs( cfg.srcs )
end

function lib( lib_name, srcs )
	assert( type( srcs ) == "table", "srcs should be a table" )
	assert( not libs[ lib_name ] )

	local globbed = glob( srcs )
	libs[ lib_name ] = globbed
	add_srcs( globbed )
end

function prebuilt_lib( lib_name, archives )
	assert( not prebuilt_libs[ lib_name ] )
	prebuilt_libs[ lib_name ] = archives or { lib_name }
end

function prebuilt_dll( lib_name, dll )
	assert( not prebuilt_dlls[ lib_name ] )
	prebuilt_dlls[ lib_name ] = dll
end

function global_cxxflags( flags )
	cxxflags = cxxflags .. " " .. flags
end

function obj_cxxflags( pattern, flags )
	table.insert( objs_extra_flags, { pattern = pattern, flags = flags } )
end

function obj_replace_cxxflags( pattern, flags )
	table.insert( objs_flags, { pattern = pattern, flags = flags } )
end

local function toolchain_helper( t, f )
	return function( ... )
		if toolchain == t then
			f( ... )
		end
	end
end

msvc_global_cxxflags = toolchain_helper( "msvc", global_cxxflags )
msvc_obj_cxxflags = toolchain_helper( "msvc", obj_cxxflags )
msvc_obj_replace_cxxflags = toolchain_helper( "msvc", obj_replace_cxxflags )

gcc_global_cxxflags = toolchain_helper( "gcc", global_cxxflags )
gcc_obj_cxxflags = toolchain_helper( "gcc", obj_cxxflags )
gcc_obj_replace_cxxflags = toolchain_helper( "gcc", obj_replace_cxxflags )

local function sort_by_key( t )
	local ret = { }
	for k, v in pairs( t ) do
		table.insert( ret, { key = k, value = v } )
	end
	table.sort( ret, function( a, b ) return a.key < b.key end )

	function iter()
		for _, x in ipairs( ret ) do
			coroutine.yield( x.key, x.value )
		end
	end

	return coroutine.wrap( iter )
end

local function rule_for_src( src_name )
	local ext = src_name:match( "([^%.]+)$" )
	return ( { cpp = "cpp" } )[ ext ]
end

function write_ninja_script()
	printf( "builddir = build" )
	printf( "cxxflags = %s", cxxflags )
	printf( "ldflags = %s", ldflags )
	printf()

	if toolchain == "msvc" then

printf( [[
rule cpp
    command = cl /showIncludes $cxxflags $extra_cxxflags -Fo$out $in
    description = $in
    deps = msvc

rule bin
    command = link /OUT:$out $in $ldflags $extra_ldflags
    description = $out

rule lib
    command = lib /NOLOGO /OUT:$out $in
    description = $out

rule rc
    command = rc /fo$out /nologo $in_rc
    description = $in

rule copy
    command = cmd /c copy /Y $in $out
    description = $in
]] )

	elseif toolchain == "gcc" then

printf( "cpp = %s", rightmost( "cxx" ) )
printf( "ar = %s", rightmost( "ar" ) )
printf( [[
rule cpp
    command = $cpp -MD -MF $out.d $cxxflags $extra_cxxflags -c -o $out $in
    depfile = $out.d
    description = $in
    deps = gcc

rule lib
    command = $ar rs $out $in
    description = $out

rule copy
    command = cp $in $out
    description = $in
]] )

		if config ~= "release" then

printf( [[
rule bin
    command = g++ -o $out $in $ldflags $extra_ldflags
    description = $out
]] )

		else

printf( [[
rule bin
    command = g++ -o $out $in -no-pie $ldflags $extra_ldflags && objcopy --only-keep-debug $out $out.debug && strip $out
    description = $out

rule bin-static
    command = ggbuild/zig/zig build-exe --name $out $in -lc -lc++ -fno-PIE $ldflags $extra_ldflags -target x86_64-linux-musl -static && objcopy --only-keep-debug $out $out.debug && strip $out
    description = $out
]] )

		end
	end

	for _, flag in ipairs( objs_flags ) do
		for name, cfg in pairs( objs ) do
			if name:match( flag.pattern ) then
				cfg.cxxflags = flag.flags
			end
		end
	end

	for _, flag in ipairs( objs_extra_flags ) do
		for name, cfg in pairs( objs ) do
			if name:match( flag.pattern ) then
				cfg.extra_cxxflags = ( cfg.extra_cxxflags or "" ) .. " " .. flag.flags
			end
		end
	end

	for src_name, cfg in sort_by_key( objs ) do
		local rule = rule_for_src( src_name )
		printf( "build %s/%s%s: %s %s", dir, src_name, obj_suffix, rule, src_name )
		if cfg.cxxflags then
			printf( "    cxxflags = %s", cfg.cxxflags )
		end
		if cfg.extra_cxxflags then
			printf( "    extra_cxxflags = %s", cfg.extra_cxxflags )
		end
	end

	printf()

	for lib_name, srcs in sort_by_key( libs ) do
		printf( "build %s/%s%s%s: lib %s", dir, lib_prefix, lib_name, lib_suffix, join_srcs( srcs, obj_suffix ) )
	end

	printf()

	for lib_name, dll in sort_by_key( prebuilt_dlls ) do
		local src_path = "libs/" .. lib_name .. "/" ..  dll .. dll_suffix
		local dst_path = output_dir .. dll .. dll_suffix
		if OS == "windows" then
			-- copy goes beserk without this
			src_path = src_path:gsub( "/", "\\" )
			dst_path = dst_path:gsub( "/", "\\" )
		end
		printf( "build %s: copy %s", dst_path, src_path );
	end

	printf()

	for bin_name, cfg in sort_by_key( bins ) do
		local srcs = { cfg.srcs }

		if OS == "windows" and cfg.rc then
			srcs = { cfg.srcs, cfg.rc }
			-- printf( "build %s/%s%s: rc %s.rc %s.xml", dir, cfg.rc, obj_suffix, cfg.rc, cfg.rc )
			printf( "build %s/%s%s: rc %s.rc", dir, cfg.rc, obj_suffix, cfg.rc )
			printf( "    in_rc = %s.rc", cfg.rc )
		end

		local full_name = output_dir .. bin_name .. bin_suffix
		printf( "build %s: %s %s %s",
			full_name,
			( OS == "linux" and config == "release" and cfg.static_linux_release_build ) and "bin-static" or "bin",
			join_srcs( srcs, obj_suffix ),
			join_libs( cfg.libs )
		)

		local ldflags_key = toolchain .. "_ldflags"
		local extra_ldflags_key = toolchain .. "_extra_ldflags"
		if cfg[ ldflags_key ] then
			printf( "    ldflags = %s", cfg[ ldflags_key ] )
		end
		if cfg[ extra_ldflags_key ] then
			printf( "    extra_ldflags = %s", cfg[ extra_ldflags_key ] )
		end

		printf( "default %s", full_name )
	end
end
