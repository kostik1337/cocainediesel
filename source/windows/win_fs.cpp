/*
Copyright (C) 1997-2001 Id Software, Inc.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
*/

#include "windows/miniwindows.h"
#include <io.h>
#include <shlobj.h>

#include "qcommon/qcommon.h"
#include "qcommon/string.h"
#include "qcommon/fs.h"
#include "qcommon/sys_fs.h"

static char *findbase = NULL;
static char *findpath = NULL;
static size_t findpath_size = 0;
static intptr_t findhandle = -1;

/*
* CompareAttributes
*/
static bool CompareAttributes( unsigned found, unsigned musthave, unsigned canthave ) {
	if( ( found & _A_RDONLY ) && ( canthave & SFF_RDONLY ) ) {
		return false;
	}
	if( ( found & _A_HIDDEN ) && ( canthave & SFF_HIDDEN ) ) {
		return false;
	}
	if( ( found & _A_SYSTEM ) && ( canthave & SFF_SYSTEM ) ) {
		return false;
	}
	if( ( found & _A_SUBDIR ) && ( canthave & SFF_SUBDIR ) ) {
		return false;
	}
	if( ( found & _A_ARCH ) && ( canthave & SFF_ARCH ) ) {
		return false;
	}

	if( ( musthave & SFF_RDONLY ) && !( found & _A_RDONLY ) ) {
		return false;
	}
	if( ( musthave & SFF_HIDDEN ) && !( found & _A_HIDDEN ) ) {
		return false;
	}
	if( ( musthave & SFF_SYSTEM ) && !( found & _A_SYSTEM ) ) {
		return false;
	}
	if( ( musthave & SFF_SUBDIR ) && !( found & _A_SUBDIR ) ) {
		return false;
	}
	if( ( musthave & SFF_ARCH ) && !( found & _A_ARCH ) ) {
		return false;
	}

	return true;
}

/*
* _Sys_Utf8FileNameToWide
*/
static void _Sys_Utf8FileNameToWide( const char *utf8name, wchar_t *wname, size_t wchars ) {
	MultiByteToWideChar( CP_UTF8, 0, utf8name, -1, wname, wchars );
	wname[wchars - 1] = '\0';
}

/*
* _Sys_WideFileNameToUtf8
*/
static void _Sys_WideFileNameToUtf8( const wchar_t *wname, char *utf8name, size_t utf8chars ) {
	WideCharToMultiByte( CP_UTF8, 0, wname, -1, utf8name, utf8chars, NULL, NULL );
	utf8name[utf8chars - 1] = '\0';
}

/*
* Sys_FS_FindFirst
*/
const char *Sys_FS_FindFirst( const char *path, unsigned musthave, unsigned canthave ) {
	size_t size;
	struct _wfinddata_t findinfo;
	char finame[MAX_PATH];
	WCHAR wpath[MAX_PATH];

	assert( path );
	assert( findhandle == -1 );
	assert( !findbase && !findpath && !findpath_size );

	if( findhandle != -1 ) {
		Sys_Error( "Sys_FindFirst without close" );
	}

	findbase = ( char * ) Mem_TempMalloc( sizeof( char ) * ( strlen( path ) + 1 ) );
	Q_strncpyz( findbase, path, ( strlen( path ) + 1 ) );
	COM_StripFilename( findbase );

	_Sys_Utf8FileNameToWide( path, wpath, ARRAY_COUNT( wpath ) );

	findhandle = _wfindfirst( wpath, &findinfo );

	if( findhandle == -1 ) {
		return NULL;
	}

	_Sys_WideFileNameToUtf8( findinfo.name, finame, sizeof( finame ) );

	if( strcmp( finame, "." ) && strcmp( finame, ".." ) &&
		CompareAttributes( findinfo.attrib, musthave, canthave ) ) {
		size_t finame_len = strlen( finame );
		size = sizeof( char ) * ( strlen( findbase ) + 1 + finame_len + 1 + 1 );
		if( findpath_size < size ) {
			if( findpath ) {
				Mem_TempFree( findpath );
			}
			findpath_size = size * 2; // extra space to reduce reallocs
			findpath = ( char * ) Mem_TempMalloc( findpath_size );
		}

		snprintf( findpath, findpath_size, "%s/%s%s", findbase, finame,
					 ( findinfo.attrib & _A_SUBDIR ) && finame[finame_len - 1] != '/' ? "/" : "" );
		return findpath;
	}

	return Sys_FS_FindNext( musthave, canthave );
}

/*
* Sys_FS_FindNext
*/
const char *Sys_FS_FindNext( unsigned musthave, unsigned canthave ) {
	size_t size;
	struct _wfinddata_t findinfo;
	char finame[MAX_PATH];

	assert( findhandle != -1 );
	assert( findbase );

	if( findhandle == -1 ) {
		return NULL;
	}

	while( _wfindnext( findhandle, &findinfo ) != -1 ) {
		_Sys_WideFileNameToUtf8( findinfo.name, finame, sizeof( finame ) );

		if( strcmp( finame, "." ) && strcmp( finame, ".." ) &&
			CompareAttributes( findinfo.attrib, musthave, canthave ) ) {
			size_t finame_len = strlen( finame );
			size = sizeof( char ) * ( strlen( findbase ) + 1 + finame_len + 1 + 1 );
			if( findpath_size < size ) {
				if( findpath ) {
					Mem_TempFree( findpath );
				}
				findpath_size = size * 2; // extra space to reduce reallocs
				findpath = ( char * ) Mem_TempMalloc( findpath_size );
			}

			snprintf( findpath, findpath_size, "%s/%s%s", findbase, finame,
						 ( findinfo.attrib & _A_SUBDIR ) && finame[finame_len - 1] != '/' ? "/" : "" );
			return findpath;
		}
	}

	return NULL;
}

/*
* Sys_FS_FindClose
*/
void Sys_FS_FindClose() {
	assert( findbase );

	if( findhandle != -1 ) {
		_findclose( findhandle );
		findhandle = -1;
	}

	Mem_TempFree( findbase );
	findbase = NULL;

	if( findpath ) {
		Mem_TempFree( findpath );
		findpath = NULL;
		findpath_size = 0;
	}
}

/*
* Sys_FS_GetHomeDirectory
*/
const char *Sys_FS_GetHomeDirectory() {
	int csidl = CSIDL_PERSONAL;

	static char home[MAX_PATH] = { '\0' };
	if( home[0] != '\0' ) {
		return home;
	}

	SHGetFolderPath( 0, csidl, 0, 0, home );

	if( home[0] == '\0' ) {
		return NULL;
	}

	Q_strncpyz( home, va( "%s/My Games/%s 0.0", COM_SanitizeFilePath( home ), APPLICATION ), sizeof( home ) );

	return home;
}

/*
* Sys_FS_CreateDirectory
*/
bool Sys_FS_CreateDirectory( const char *path ) {
	return CreateDirectoryA( path, NULL ) != 0 || GetLastError() == ERROR_ALREADY_EXISTS;
}

/*
* Sys_FS_FileNo
*/
int Sys_FS_FileNo( FILE *fp ) {
	return _fileno( fp );
}

static wchar_t * UTF8ToWide( Allocator * a, const char * utf8 ) {
	int len = MultiByteToWideChar( CP_UTF8, 0, utf8, -1, NULL, 0 );
	assert( len != 0 );

	wchar_t * wide = ALLOC_MANY( a, wchar_t, len );
	MultiByteToWideChar( CP_UTF8, 0, utf8, -1, wide, len );

	return wide;
}

static char * WideToUTF8( Allocator * a, const wchar_t * wide ) {
	int len = WideCharToMultiByte( CP_UTF8, 0, wide, -1, NULL, 0, NULL, NULL );
	assert( len != 0 );

	char * utf8 = ALLOC_MANY( a, char, len );
	WideCharToMultiByte( CP_UTF8, 0, wide, -1, utf8, len, NULL, NULL );

	return utf8;
}

FILE * OpenFile( Allocator * a, const char * path, const char * mode ) {
	wchar_t * widepath = UTF8ToWide( a, path );
	wchar_t * widemode = UTF8ToWide( a, mode );
	defer { FREE( a, widepath ); };
	defer { FREE( a, widemode ); };
	return _wfopen( widepath, widemode );
}

struct ListDirHandleImpl {
	HANDLE handle;
	Allocator * a;
	WIN32_FIND_DATAW * ffd;
	char * utf8_path;
	bool first;
};

STATIC_ASSERT( sizeof( ListDirHandleImpl ) <= sizeof( ListDirHandle ) );

static ListDirHandleImpl OpaqueToImpl( ListDirHandle opaque ) {
	ListDirHandleImpl impl;
	memcpy( &impl, opaque.impl, sizeof( impl ) );
	return impl;
}

static ListDirHandle ImplToOpaque( ListDirHandleImpl impl ) {
	ListDirHandle opaque;
	memcpy( opaque.impl, &impl, sizeof( impl ) );
	return opaque;
}

ListDirHandle BeginListDir( Allocator * a, const char * path ) {
	ListDirHandleImpl handle = { };
	handle.a = a;
	handle.ffd = ALLOC( a, WIN32_FIND_DATAW );
	handle.first = true;

	DynamicString path_and_wildcard( a, "{}/*", path );

	wchar_t * wide = UTF8ToWide( a, path_and_wildcard.c_str() );
	defer { FREE( a, wide ); };

	handle.handle = FindFirstFileW( wide, handle.ffd );
	if( handle.handle == INVALID_HANDLE_VALUE ) {
		FREE( handle.a, handle.ffd );
		handle.handle = NULL;
	}

	return ImplToOpaque( handle );
}

bool ListDirNext( ListDirHandle * opaque, const char ** path, bool * dir ) {
	ListDirHandleImpl handle = OpaqueToImpl( *opaque );
	if( handle.handle == NULL )
		return false;

	FREE( handle.a, handle.utf8_path );

	if( !handle.first ) {
		if( FindNextFileW( handle.handle, handle.ffd ) == 0 ) {
			FindClose( handle.handle );
			FREE( handle.a, handle.ffd );
			return false;
		}
	}

	handle.utf8_path = WideToUTF8( handle.a, handle.ffd->cFileName );
	handle.first = false;

	*path = handle.utf8_path;
	*dir = ( handle.ffd->dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY ) != 0;

	*opaque = ImplToOpaque( handle );

	return true;
}

s64 FileLastModifiedTime( TempAllocator * temp, const char * path ) {
	wchar_t * wide = UTF8ToWide( temp, path );

	HANDLE handle = CreateFileW( wide, 0, 0, NULL, OPEN_EXISTING, 0, NULL );
	if( handle == INVALID_HANDLE_VALUE ) {
		return 0;
	}

	defer { CloseHandle( handle ); };

	FILETIME modified;
	if( GetFileTime( handle, NULL, NULL, &modified ) == 0 ) {
		return 0;
	}

	ULARGE_INTEGER modified64;
	memcpy( &modified64, &modified, sizeof( modified ) );
	return modified64.QuadPart;
}
