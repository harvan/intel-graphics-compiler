/*========================== begin_copyright_notice ============================

Copyright (C) 2022 Intel Corporation

SPDX-License-Identifier: MIT

============================= end_copyright_notice ===========================*/

#include "IBiF_intel_rt_struct_defs.cl"


void* intel_get_rt_stack(rtglobals_t rt_dispatch_globals)
{
    return __builtin_IB_intel_get_rt_stack(rt_dispatch_globals);
}

void* intel_get_thread_btd_stack(rtglobals_t rt_dispatch_globals)
{
    return __builtin_IB_intel_get_thread_btd_stack(rt_dispatch_globals);
}

void* intel_get_global_btd_stack(rtglobals_t rt_dispatch_globals)
{
    return __builtin_IB_intel_get_global_btd_stack(rt_dispatch_globals);
}

rtfence_t intel_dispatch_trace_ray_query(
    rtglobals_t rt_dispatch_globals, uint bvh_level, uint traceRayCtrl)
{
    return __builtin_IB_intel_dispatch_trace_ray_query(
        rt_dispatch_globals, bvh_level, traceRayCtrl);
}

void intel_rt_sync(rtfence_t fence)
{
    return __builtin_IB_intel_rt_sync(fence);
}

global void* intel_get_implicit_dispatch_globals()
{
    return __builtin_IB_intel_get_implicit_dispatch_globals();
}

intel_raytracing_ext_flag_t intel_get_raytracing_ext_flag()
{
    return intel_raytracing_ext_flag_ray_query;
};

intel_ray_query_t intel_ray_query_init(
    intel_ray_desc_t ray, intel_raytracing_acceleration_structure_t accel)
{
    global HWAccel* hwaccel   = to_global((HWAccel*)accel);
    unsigned int    bvh_level = 0;

    rtglobals_t     dispatchGlobalsPtr = (rtglobals_t)intel_get_implicit_dispatch_globals();
    global RTStack* rtStack =
        to_global((RTStack*)intel_get_rt_stack((rtglobals_t)dispatchGlobalsPtr));

    /* init ray */
    rtStack->ray[bvh_level].org[0] = ray.origin.x;
    rtStack->ray[bvh_level].org[1] = ray.origin.y;
    rtStack->ray[bvh_level].org[2] = ray.origin.z;
    rtStack->ray[bvh_level].dir[0] = ray.direction.x;
    rtStack->ray[bvh_level].dir[1] = ray.direction.y;
    rtStack->ray[bvh_level].dir[2] = ray.direction.z;
    rtStack->ray[bvh_level].tnear  = ray.tmin;
    rtStack->ray[bvh_level].tfar   = ray.tmax;

    rtStack->ray[bvh_level].data[1] = 0;
    rtStack->ray[bvh_level].data[2] = 0;
    rtStack->ray[bvh_level].data[3] = 0;

    MemRay_setRootNodePtr(&rtStack->ray[bvh_level], (ulong)accel + 128);
    MemRay_setRayFlags(&rtStack->ray[bvh_level],    ray.flags);
    MemRay_setRayMask(&rtStack->ray[bvh_level],     ray.mask);

    MemHit_clear(&rtStack->hit[COMMITTED], /*done=*/0, /*valid=*/0);
    MemHit_clear(&rtStack->hit[POTENTIAL], /*done=*/1, /*valid=*/1);
    rtStack->hit[COMMITTED].t = INFINITY;
    rtStack->hit[POTENTIAL].t = INFINITY;

    intel_ray_query_t rayquery = __builtin_IB_intel_init_ray_query(
        NULL,
        dispatchGlobalsPtr,
        rtStack,
        TRACE_RAY_INITIAL,
        bvh_level
    );

    return rayquery;
}

void intel_ray_query_forward_ray(
    intel_ray_query_t                         rayquery,
    intel_ray_desc_t                          ray,
    intel_raytracing_acceleration_structure_t accel_i)
{
    HWAccel* accel = (HWAccel*)accel_i;
    global RTStack* rtStack = __builtin_IB_intel_query_rt_stack(rayquery);

    /* init ray */
    uint bvh_level = __builtin_IB_intel_query_bvh_level(rayquery) + 1;

    rtStack->ray[bvh_level].org[0] = ray.origin.x;
    rtStack->ray[bvh_level].org[1] = ray.origin.y;
    rtStack->ray[bvh_level].org[2] = ray.origin.z;
    rtStack->ray[bvh_level].dir[0] = ray.direction.x;
    rtStack->ray[bvh_level].dir[1] = ray.direction.y;
    rtStack->ray[bvh_level].dir[2] = ray.direction.z;
    rtStack->ray[bvh_level].tnear  = ray.tmin;
    rtStack->ray[bvh_level].tfar   = ray.tmax;

    rtStack->ray[bvh_level].data[1] = 0;
    rtStack->ray[bvh_level].data[2] = 0;
    rtStack->ray[bvh_level].data[3] = 0;

    MemRay_setRootNodePtr(&rtStack->ray[bvh_level], (ulong)accel + 128);
    MemRay_setRayFlags(&rtStack->ray[bvh_level],    ray.flags);
    MemRay_setRayMask(&rtStack->ray[bvh_level],     ray.mask);

    __builtin_IB_intel_update_ray_query(
        rayquery,
        NULL,
        __builtin_IB_intel_query_rt_globals(rayquery),
        rtStack,
        TRACE_RAY_INSTANCE,
        bvh_level
    );
}

void intel_ray_query_commit_potential_hit(intel_ray_query_t rayquery)
{
    global RTStack* rtStack = __builtin_IB_intel_query_rt_stack(rayquery);

    uint bvh_level = __builtin_IB_intel_query_bvh_level(rayquery);
    uint rflags    = MemRay_getRayFlags(&rtStack->ray[bvh_level]);

    if (rflags & intel_ray_flags_accept_first_hit_and_end_search)
    {
        rtStack->hit[COMMITTED] = rtStack->hit[POTENTIAL];
        MemHit_setValid(&rtStack->hit[COMMITTED], 1);

        __builtin_IB_intel_update_ray_query(
            rayquery,
            NULL,
            __builtin_IB_intel_query_rt_globals(rayquery),
            rtStack,
            TRACE_RAY_DONE,
            bvh_level
        );
    }
    else
    {
        MemHit_setValid(&rtStack->hit[POTENTIAL], 1); // FIXME: is this required?

        __builtin_IB_intel_update_ray_query(
            rayquery,
            NULL,
            __builtin_IB_intel_query_rt_globals(rayquery),
            rtStack,
            TRACE_RAY_COMMIT,
            bvh_level
        );
    }
}

void intel_ray_query_commit_potential_hit_override(
    intel_ray_query_t rayquery, float override_hit_distance, intel_float2 override_uv)
{
    global RTStack*         rtStack  = __builtin_IB_intel_query_rt_stack(rayquery);

    rtStack->hit[POTENTIAL].t = override_hit_distance;
    rtStack->hit[POTENTIAL].u = override_uv.x;
    rtStack->hit[POTENTIAL].v = override_uv.y;

    intel_ray_query_commit_potential_hit(rayquery);
}

void intel_ray_query_start_traversal(intel_ray_query_t rayquery)
{
    rtglobals_t             dispatchGlobalsPtr = __builtin_IB_intel_query_rt_globals(rayquery);
    global RTStack*         rtStack            = __builtin_IB_intel_query_rt_stack(rayquery);

    MemHit_setDone(&rtStack->hit[POTENTIAL], 1);
    MemHit_setValid(&rtStack->hit[POTENTIAL], 1);

    TraceRayCtrl ctrl = __builtin_IB_intel_query_ctrl(rayquery);

    if (ctrl == TRACE_RAY_DONE) return;

    uint bvh_level = __builtin_IB_intel_query_bvh_level(rayquery);

    rtfence_t fence = intel_dispatch_trace_ray_query(
        dispatchGlobalsPtr, bvh_level, ctrl);

    __builtin_IB_intel_update_ray_query(
        rayquery,
        fence,
        dispatchGlobalsPtr,
        rtStack,
        ctrl,
        bvh_level
    );
}

void intel_ray_query_sync(intel_ray_query_t rayquery)
{
    rtfence_t fence = __builtin_IB_intel_query_rt_fence(rayquery);
    intel_rt_sync(fence);

    global RTStack* rtStack = __builtin_IB_intel_query_rt_stack(rayquery);

    uint bvh_level = MemHit_getBvhLevel(&rtStack->hit[POTENTIAL]);

     __builtin_IB_intel_update_ray_query(
        rayquery,
        fence,
        __builtin_IB_intel_query_rt_globals(rayquery),
        rtStack,
        TRACE_RAY_CONTINUE,
        bvh_level
    );
}

void intel_ray_query_abandon(intel_ray_query_t rayquery)
{
    intel_ray_query_sync(rayquery);

    __builtin_IB_intel_update_ray_query(
        rayquery,
        NULL,
        NULL,
        NULL,
        TRACE_RAY_INITIAL,
        0
    );
}

uint intel_get_hit_bvh_level(intel_ray_query_t rayquery, intel_hit_type_t hit_type)
{
    return MemHit_getBvhLevel(get_query_hit(rayquery, hit_type));
}

float intel_get_hit_distance(
    intel_ray_query_t rayquery, intel_hit_type_t hit_type)
{
    return get_query_hit(rayquery, hit_type)->t;
}

intel_float2 intel_get_hit_barycentrics(intel_ray_query_t rayquery, intel_hit_type_t hit_type)
{
    MemHit* hit = get_query_hit(rayquery, hit_type);
    return (intel_float2){hit->u, hit->v};
}

bool intel_get_hit_front_face(
    intel_ray_query_t rayquery, intel_hit_type_t hit_type)
{
    return MemHit_getFrontFace(get_query_hit(rayquery, hit_type));
}

uint intel_get_hit_geometry_id(
    intel_ray_query_t rayquery, intel_hit_type_t hit_type)
{
    MemHit* hit = get_query_hit(rayquery, hit_type);

    PrimLeafDesc* leaf = (PrimLeafDesc*)MemHit_getPrimLeafPtr(hit);
    return PrimLeafDesc_getGeomIndex(leaf);
}

uint intel_get_hit_primitive_id(
    intel_ray_query_t rayquery, intel_hit_type_t hit_type)
{
    MemHit*       hit  = get_query_hit(rayquery, hit_type);
    PrimLeafDesc* leaf = (PrimLeafDesc*)MemHit_getPrimLeafPtr(hit);

    if (MemHit_getLeafType(hit) == NODE_TYPE_QUAD)
        return ((QuadLeaf*)leaf)->primIndex0 + MemHit_getPrimIndexDelta(hit);
    else
        return ((ProceduralLeaf*)leaf)->_primIndex[MemHit_getPrimLeafIndex(hit)];
}

uint intel_get_hit_triangle_primitive_id(
    intel_ray_query_t rayquery, intel_hit_type_t hit_type)
{
    MemHit*   hit  = get_query_hit(rayquery, hit_type);
    QuadLeaf* leaf = (QuadLeaf*)MemHit_getPrimLeafPtr(hit);

    return leaf->primIndex0 + MemHit_getPrimIndexDelta(hit);
}

uint intel_get_hit_procedural_primitive_id(
    intel_ray_query_t rayquery, intel_hit_type_t hit_type)
{
    MemHit*         hit  = get_query_hit(rayquery, hit_type);
    ProceduralLeaf* leaf = (ProceduralLeaf*)MemHit_getPrimLeafPtr(hit);
    return leaf->_primIndex[MemHit_getPrimLeafIndex(hit)];
}

uint intel_get_hit_instance_id(
    intel_ray_query_t rayquery, intel_hit_type_t hit_type)
{
    MemHit*       hit  = get_query_hit(rayquery, hit_type);
    InstanceLeaf* leaf = (InstanceLeaf*)MemHit_getInstanceLeafPtr(hit);
    if (leaf == NULL) return -1;
    return leaf->part1.instanceIndex;
}

uint intel_get_hit_instance_user_id(
    intel_ray_query_t rayquery, intel_hit_type_t hit_type)
{
    MemHit*       hit  = get_query_hit(rayquery, hit_type);
    InstanceLeaf* leaf = (InstanceLeaf*)MemHit_getInstanceLeafPtr(hit);
    if (leaf == NULL) return -1;
    return leaf->part1.instanceID;
}

intel_float4x3 intel_get_hit_world_to_object(
    intel_ray_query_t rayquery, intel_hit_type_t hit_type)
{
    MemHit*       hit  = get_query_hit(rayquery, hit_type);
    InstanceLeaf* leaf = (InstanceLeaf*)MemHit_getInstanceLeafPtr(hit);

    if (leaf == NULL) return (intel_float4x3){{1, 0, 0}, {0, 1, 0}, {0, 0, 1}, {0, 0, 0}};

    return (intel_float4x3) {
        {leaf->part0.world2obj_vx[0],
         leaf->part0.world2obj_vx[1],
         leaf->part0.world2obj_vx[2]},
        {leaf->part0.world2obj_vy[0],
         leaf->part0.world2obj_vy[1],
         leaf->part0.world2obj_vy[2]},
        {leaf->part0.world2obj_vz[0],
         leaf->part0.world2obj_vz[1],
         leaf->part0.world2obj_vz[2]},
        {leaf->part1.world2obj_p[0],
         leaf->part1.world2obj_p[1],
         leaf->part1.world2obj_p[2]}};
}

intel_float4x3 intel_get_hit_object_to_world(
    intel_ray_query_t rayquery, intel_hit_type_t hit_type)
{
    MemHit*       hit  = get_query_hit(rayquery, hit_type);
    InstanceLeaf* leaf = (InstanceLeaf*)MemHit_getInstanceLeafPtr(hit);
    if (leaf == NULL) return (intel_float4x3){{1, 0, 0}, {0, 1, 0}, {0, 0, 1}, {0, 0, 0}};
    return (intel_float4x3) {
        {leaf->part1.obj2world_vx[0],
         leaf->part1.obj2world_vx[1],
         leaf->part1.obj2world_vx[2]},
        {leaf->part1.obj2world_vy[0],
         leaf->part1.obj2world_vy[1],
         leaf->part1.obj2world_vy[2]},
        {leaf->part1.obj2world_vz[0],
         leaf->part1.obj2world_vz[1],
         leaf->part1.obj2world_vz[2]},
        {leaf->part0.obj2world_p[0],
         leaf->part0.obj2world_p[1],
         leaf->part0.obj2world_p[2]}};
}

intel_candidate_type_t
intel_get_hit_candidate(intel_ray_query_t rayquery, intel_hit_type_t hit_type)
{
    return MemHit_getLeafType(get_query_hit(rayquery, hit_type)) == NODE_TYPE_QUAD
               ? intel_candidate_type_triangle
               : intel_candidate_type_procedural;
}

// fetch triangle vertices for a hit
void intel_get_hit_triangle_vertices(
    intel_ray_query_t rayquery, intel_float3 vertices_out[3], intel_hit_type_t hit_type)
{
    MemHit*         hit  = get_query_hit(rayquery, hit_type);
    const QuadLeaf* leaf = (QuadLeaf*)MemHit_getPrimLeafPtr(hit);

    unsigned int j0 = 0, j1 = 1, j2 = 2;
    if (MemHit_getPrimLeafIndex(hit) != 0)
    {
        j0 = QuadLeaf_getJ0(leaf);
        j1 = QuadLeaf_getJ1(leaf);
        j2 = QuadLeaf_getJ2(leaf);
    }

    vertices_out[0] = (intel_float3){leaf->v[j0][0], leaf->v[j0][1], leaf->v[j0][2]};
    vertices_out[1] = (intel_float3){leaf->v[j1][0], leaf->v[j1][1], leaf->v[j1][2]};
    vertices_out[2] = (intel_float3){leaf->v[j2][0], leaf->v[j2][1], leaf->v[j2][2]};
}

// Read ray-data. This is used to read transformed rays produced by HW instancing pipeline
// during any-hit or intersection shader execution.
intel_float3 intel_get_ray_origin(intel_ray_query_t rayquery, uint bvh_level)
{
    global RTStack*         rtStack  = __builtin_IB_intel_query_rt_stack(rayquery);

    global MemRay* ray = &rtStack->ray[bvh_level];
    return (intel_float3){ray->org[0], ray->org[1], ray->org[2]};
}

intel_float3 intel_get_ray_direction(intel_ray_query_t rayquery, uint bvh_level)
{
    global RTStack*         rtStack  = __builtin_IB_intel_query_rt_stack(rayquery);

    global MemRay* ray = &rtStack->ray[bvh_level];
    return (intel_float3){ray->dir[0], ray->dir[1], ray->dir[2]};
}

float intel_get_ray_tmin(intel_ray_query_t rayquery, uint bvh_level)
{
    global RTStack*         rtStack  = __builtin_IB_intel_query_rt_stack(rayquery);

    return rtStack->ray[bvh_level].tnear;
}

intel_ray_flags_t intel_get_ray_flags(intel_ray_query_t rayquery, uint bvh_level)
{
    global RTStack*         rtStack  = __builtin_IB_intel_query_rt_stack(rayquery);

    return (intel_ray_flags_t)MemRay_getRayFlags(&rtStack->ray[bvh_level]);
}

int intel_get_ray_mask(intel_ray_query_t rayquery, uint bvh_level)
{
    global RTStack*         rtStack  = __builtin_IB_intel_query_rt_stack(rayquery);

    return MemRay_getRayMask(&rtStack->ray[bvh_level]);
}

// Test whether traversal has terminated.  If false, the ray has reached
// a procedural leaf or a non-opaque triangle leaf, and requires shader processing.
bool intel_is_traversal_done(intel_ray_query_t rayquery)
{
    return MemHit_getDone(get_query_hit(rayquery, intel_hit_type_potential_hit));
}

// if traversal is done one can test for the presence of a committed hit to either invoke miss or closest hit shader
bool intel_has_committed_hit(intel_ray_query_t rayquery)
{
    return MemHit_getValid(get_query_hit(rayquery, intel_hit_type_committed_hit));
}
