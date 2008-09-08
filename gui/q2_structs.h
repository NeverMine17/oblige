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

//
// qfiles.h: quake file formats
// This file must be identical in the quake and utils directories
//


//
// Modified by Andrew Apted for OBLIGE Level Maker,
//
#ifndef __QUAKE2_FILES_H__
#define __QUAKE2_FILES_H__


/*
==============================================================================

  .BSP file format

==============================================================================
*/

#define IDBSPHEADER  (('P'<<24)+('S'<<16)+('B'<<8)+'I')
  // little-endian "IBSP"

#define BSPVERSION  38


// upper design bounds
// leaffaces, leafbrushes, planes, and verts are still bounded by
// 16 bit short limits
#define MAX_MAP_MODELS     1024
#define MAX_MAP_BRUSHES    8192
#define MAX_MAP_ENTITIES   2048
#define MAX_MAP_TEXINFO    8192

#define MAX_MAP_PLANES        65536
#define MAX_MAP_NODES         65536
#define MAX_MAP_BRUSHSIDES    65536
#define MAX_MAP_LEAFS         65536
#define MAX_MAP_VERTS         65536
#define MAX_MAP_FACES         65536
#define MAX_MAP_LEAFFACES     65536
#define MAX_MAP_LEAFBRUSHES   65536
#define MAX_MAP_PORTALS       65536

#define MAX_MAP_AREAS           256
#define MAX_MAP_AREAPORTALS    1024
#define MAX_MAP_EDGES        128000
#define MAX_MAP_SURFEDGES    256000
#define MAX_MAP_LIGHTING   0x200000
#define MAX_MAP_VISIBILITY 0x100000
#define MAX_MAP_ENTSTRING   0x40000

// key / value pair sizes

#define MAX_KEY    32
#define MAX_VALUE  1024

//=============================================================================

#define LUMP_ENTITIES     0
#define LUMP_PLANES       1
#define LUMP_VERTEXES     2
#define LUMP_VISIBILITY   3
#define LUMP_NODES        4
#define LUMP_TEXINFO      5
#define LUMP_FACES        6
#define LUMP_LIGHTING     7
#define LUMP_LEAFS        8
#define LUMP_LEAFFACES    9
#define LUMP_LEAFBRUSHES  10
#define LUMP_EDGES        11
#define LUMP_SURFEDGES    12
#define LUMP_MODELS       13
#define LUMP_BRUSHES      14
#define LUMP_BRUSHSIDES   15
#define LUMP_POP          16
#define LUMP_AREAS        17
#define LUMP_AREAPORTALS  18

#define HEADER_LUMPS      19

typedef struct
{
  char   ident[4];
  s32_t  version;  

  lump_t lumps[HEADER_LUMPS];
}
dheader2_t;

typedef struct
{
  float mins[3], maxs[3];
  float origin[3];   // for sounds or lights

  s32_t headnode;
  s32_t firstface, numfaces;  // submodels just draw faces
                              // without walking the bsp tree
}
dmodel_t;

typedef struct
{
  float x, y, z;
}
dvertex_t;


// 0-2 are axial planes
#define PLANE_X      0
#define PLANE_Y      1
#define PLANE_Z      2

// 3-5 are non-axial planes snapped to the nearest
#define PLANE_ANYX    3
#define PLANE_ANYY    4
#define PLANE_ANYZ    5

// planes (x&~1) and (x&~1)+1 are always opposites

typedef struct
{
  float normal[3];
  float dist;
  s32_t type;    // PLANE_X - PLANE_ANYZ
}
dplane_t;


// contents flags are seperate bits
// a given brush can contribute multiple content bits
// multiple brushes can be in a single leaf

// these definitions also need to be in q_shared.h!

// lower bits are stronger, and will eat weaker brushes completely
#define CONTENTS_SOLID      1    // an eye is never valid in a solid
#define CONTENTS_WINDOW      2    // translucent, but not watery
#define CONTENTS_AUX      4
#define CONTENTS_LAVA      8
#define CONTENTS_SLIME      16
#define CONTENTS_WATER      32
#define CONTENTS_MIST      64
#define LAST_VISIBLE_CONTENTS  64

// remaining contents are non-visible, and don't eat brushes

#define CONTENTS_AREAPORTAL    0x8000

#define CONTENTS_PLAYERCLIP    0x10000
#define CONTENTS_MONSTERCLIP  0x20000

// currents can be added to any other contents, and may be mixed
#define CONTENTS_CURRENT_0    0x40000
#define CONTENTS_CURRENT_90    0x80000
#define CONTENTS_CURRENT_180  0x100000
#define CONTENTS_CURRENT_270  0x200000
#define CONTENTS_CURRENT_UP    0x400000
#define CONTENTS_CURRENT_DOWN  0x800000

#define CONTENTS_ORIGIN      0x1000000  // removed before bsping an entity

#define CONTENTS_MONSTER    0x2000000  // should never be on a brush, only in game
#define CONTENTS_DEADMONSTER  0x4000000
#define CONTENTS_DETAIL      0x8000000  // brushes to be added after vis leafs
#define CONTENTS_TRANSLUCENT  0x10000000  // auto set if any surface has trans
#define CONTENTS_LADDER      0x20000000




typedef struct
{
  s32_t planenum;
  s32_t children[2];  // negative numbers are -(leafs+1), not nodes

  s16_t mins[3];    // for frustom culling
  s16_t maxs[3];

  u16_t firstface;
  u16_t numfaces;  // counting both sides
}
dnode_t;


#define SURF_LIGHT     0x1   // value will hold the light strength
#define SURF_SLICK     0x2   // effects game physics
#define SURF_SKY       0x4   // don't draw, but add to skybox
#define SURF_WARP      0x8   // turbulent water warp
#define SURF_TRANS33  0x10
#define SURF_TRANS66  0x20
#define SURF_FLOWING  0x40   // scroll towards angle
#define SURF_NODRAW   0x80   // don't bother referencing the texture


typedef struct texinfo_s
{
  float s[4];   // x/y/z/offset
  float t[4];

  u32_t flags;  // miptex flags + overrides
  s32_t value;  // light emission, etc

  char  texture[32];  // texture name (textures/*.wal)
  s32_t anim_next;    // for animations, -1 = end of chain
}
texinfo_t;


// note that edge 0 is never used, because negative edge nums are used for
// counterclockwise use of the edge in a face
typedef struct
{
  u16_t v[2];    // vertex numbers
}
dedge_t;

#define MAXLIGHTMAPS  4
typedef struct
{
  s16_t planenum;
  s16_t side;

  s32_t firstedge;    // we must support > 64k edges
  s16_t numedges;
  s16_t texinfo;

  // lighting info
  u8_t  styles[MAXLIGHTMAPS];
  s32_t lightofs;   // start of [numstyles*surfsize] samples
}
dface_t;

typedef struct
{
  u32_t contents;      // OR of all brushes

  s16_t cluster;
  s16_t area;

  s16_t mins[3];      // for frustum culling
  s16_t maxs[3];

  u16_t first_leafface;
  u16_t num_leaffaces;

  u16_t first_leafbrush;
  u16_t num_leafbrushes;
}
dleaf_t;

typedef struct
{
  u16_t planenum;    // facing out of the leaf
  u16_t texinfo;
}
dbrushside_t;

typedef struct
{
  u16_t firstside;
  u16_t numsides;

  u32_t contents;
}
dbrush_t;

#define ANGLE_UP  -1
#define ANGLE_DOWN  -2


// the visibility lump consists of a header with a count, then
// byte offsets for the PVS and PHS of each cluster, then the raw
// compressed bit vectors
#define DVIS_PVS  0
#define DVIS_PHS  1
typedef struct
{
  int      numclusters;
  int      bitofs[8][2];  // bitofs[numclusters][2]
}
dvis_t;

// each area has a list of portals that lead into other areas
// when portals are closed, other areas may not be visible or
// hearable even if the vis info says that it could be.
typedef struct
{
  int    portalnum;
  int    otherarea;
}
dareaportal_t;

typedef struct
{
  int    numareaportals;
  int    firstareaportal;
}
darea_t;

#endif /* __QUAKE2_FILES_H__ */

//--- editor settings ---
// vi:ts=2:sw=2:expandtab
