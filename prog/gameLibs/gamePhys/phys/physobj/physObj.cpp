#include <gamePhys/phys/physObj/physObj.h>
#include <gamePhys/collision/collisionLib.h>
#include <gamePhys/collision/contactData.h>
#include <ioSys/dag_dataBlock.h>
#include <gamePhys/collision/collisionResponse.h>
#include <gamePhys/props/atmosphere.h>
#include <memory/dag_framemem.h>
#include <debug/dag_debug3d.h>
#include <gameRes/dag_collisionResource.h>
#include <scene/dag_physMat.h>
#include <math/dag_mathUtils.h>
#include <gamePhys/phys/rendinstDestr.h>
#include <gamePhys/phys/queries.h>
#include <gamePhys/collision/cachedCollisionObject.h>
#include <util/dag_finally.h>

void PhysObjState::reset()
{
  velocity.zero();
  omega.zero();
  alpha.zero();
  acceleration.zero();
  addForce.zero();
  addMoment.zero();
  logCCD = false;
  isSleep = false;
  sleepTimer = 0.f;
}

#define DO_PHYSOBJ_MEMBERS \
  SR(atTick)               \
  SR(location)             \
  SR(velocity)             \
  SR(omega)                \
  SR(alpha)                \
  SR(acceleration)         \
  SR(addForce)             \
  SR(addMoment)            \
  SR(isSleep)


void PhysObjState::serialize(danet::BitStream &bs) const
{
#define SR(x) bs.Write(x);
  DO_PHYSOBJ_MEMBERS
#undef SR
  write_controls_tick_delta(bs, atTick, lastAppliedControlsForTick);
}
bool PhysObjState::deserialize(const danet::BitStream &bs, IPhysBase &)
{
#define SR(x)      \
  if (!bs.Read(x)) \
    return false;
  DO_PHYSOBJ_MEMBERS
#undef SR
  return read_controls_tick_delta(bs, atTick, lastAppliedControlsForTick);
}

void PhysObjState::applyPartialState(const CommonPhysPartialState &state)
{
  location = state.location;
  velocity = state.velocity;
}

void PhysObjState::applyDesyncedState(const PhysObjState & /*state*/) {}


void PhysObjControlState::serialize(danet::BitStream &bs) const
{
  bs.Write(producedAtTick);
  bs.Write(sequenceNumber);
  bs.Write(unitVersion);

  const uint16_t customBits = customControls.GetNumberOfBitsUsed();
  bs.Write(customBits);
  if (customBits > 0)
    bs.WriteBits(customControls.GetData(), customBits);
}

bool PhysObjControlState::deserialize(const danet::BitStream &bs_unsafe, IPhysBase &, int32_t &)
{
  bool isOk = true;

  isOk &= bs_unsafe.Read(producedAtTick);
  isOk &= bs_unsafe.Read(sequenceNumber);
  isOk &= bs_unsafe.Read(unitVersion);

  uint16_t customBits = 0;
  isOk &= bs_unsafe.Read(customBits);

  if (customBits > 0)
  {
    customControls.reserveBits(customBits);
    isOk &= bs_unsafe.ReadBits(customControls.GetData(), customBits);
    customControls.SetWriteOffset(customBits);
  }

  return isOk;
}

void PhysObjControlState::interpolate(const PhysObjControlState &a, const PhysObjControlState &b, float k, int /*sequence_number*/)
{
  producedAtTick = lerp(a.producedAtTick, b.producedAtTick, k);
  sequenceNumber = a.sequenceNumber;
  customControls = k > 0.5f ? b.customControls : a.customControls;
}

void PhysObjControlState::serializeMinimalState(danet::BitStream &, const PhysObjControlState &) const {}
bool PhysObjControlState::deserializeMinimalState(const danet::BitStream &, const PhysObjControlState &) { return true; }

void PhysObjControlState::applyMinimalState(const PhysObjControlState &) {}

void PhysObjControlState::reset()
{
  danet::BitStream bs;
  customControls.swap(bs);
}


PhysObj::PhysObj(ptrdiff_t physactor_offset, PhysVars *phys_vars, float time_step) :
  PhysicsBase<PhysObjState, PhysObjControlState, CommonPhysPartialState>(physactor_offset, phys_vars, time_step)
{}

PhysObj::~PhysObj()
{
  for (CollisionObject &co : collision)
    dacoll::destroy_dynamic_collision(co);
  clear_and_shrink(collision);
}

void PhysObj::loadPhysParams(const DataBlock *blk)
{
  mass = blk->getReal("mass", mass);
  objDestroyMass = blk->getReal("objDestroyMass", mass);
  centerOfMass = blk->getPoint3("centerOfMass", centerOfMass);
  linearDamping = blk->getReal("linearDamping", 0.f);
  angularDamping = blk->getReal("angularDamping", 0.f);
  useMovementDamping = blk->getBool("useMovementDamping", useMovementDamping);
  omegaMovementDamping = blk->getReal("omegaMovementDamping", omegaMovementDamping);
  omegaMovementDampingThreshold = blk->getReal("omegaMovementDampingThreshold", omegaMovementDampingThreshold);
  movementDampingThreshold = blk->getReal("movementDampingThreshold", movementDampingThreshold);
  friction = blk->getReal("friction", -1.f);
  bouncing = blk->getReal("bouncing", 0.f);
  frictionGround = blk->getReal("frictionGround", 0.5f);
  bouncingGround = blk->getReal("bouncingGround", 0.f);
  limitFriction = blk->getReal("limitFriction", -1.f);
  minSpeedForBounce = blk->getReal("minSpeedForBounce", 0.f);
  momentOfInertia = blk->getPoint3("momentOfInertia", Point3(1.f, 1.f, 1.f));
  gravityMult = blk->getReal("gravityMult", gravityMult);
}

void PhysObj::loadLimits(const DataBlock *blk)
{
  velocityLimit = blk->getPoint3("velocityLimit", Point3(0.f, 0.f, 0.f));
  velocityLimitDampingMult = blk->getPoint3("velocityLimitDampingMult", Point3(-1.f, -1.f, -1.f));
  omegaLimit = blk->getPoint3("omegaLimit", Point3(0.f, 0.f, 0.f));
  omegaLimitDampingMult = blk->getPoint3("omegaLimitDampingMult", Point3(-1.f, -1.f, -1.f));
  isVelocityLimitAbsolute = blk->getBool("isVelocityLimitAbsolute", false);
  isOmegaLimitAbsolute = blk->getBool("isOmegaLimitAbsolute", false);
}

void PhysObj::loadSleepSettings(const DataBlock *blk)
{
  skipUpdateOnSleep = blk->getBool("skipUpdateOnSleep", skipUpdateOnSleep);
  sleepUpdateFrequency = blk->getInt("sleepUpdateFrequency", sleepUpdateFrequency);
  noSleepAtTheSlopeCos = blk->getReal("noSleepAtTheSlopeCos", noSleepAtTheSlopeCos);
  sleepDelay = blk->getReal("sleepDelay", sleepDelay);
}

void PhysObj::loadSolver(const DataBlock *blk)
{
  const DataBlock *solverBlk = blk->getBlockByNameEx("solver");
  linearSlop = solverBlk->getReal("linearSlop", linearSlop);
  erp = solverBlk->getReal("erp", erp);
  baumgarteBias = solverBlk->getReal("baumgarteBias", baumgarteBias);
  warmstartingFactor = solverBlk->getReal("warmstartingFactor", warmstartingFactor);
  energyConservation = solverBlk->getReal("energyConservation", energyConservation);
}

void PhysObj::loadCollisionSettings(const DataBlock *blk, const CollisionResource *coll_res)
{
  boundingRadius = blk->getReal("boundingRadius", -1.f);
  useFutureContacts = blk->getBool("useFutureContacts", false);
  shouldTraceGround = blk->getBool("shouldTraceGround", false);
  currentState.logCCD = blk->getBool("logCCD", false);
  physMatId = PhysMat::getMaterialId(blk->getStr("physMat", "default"));
  ignoreCollision = blk->getBool("ignoreCollision", ignoreCollision);
  addToWorld = blk->getBool("addToWorld", addToWorld);

  using namespace dacoll;
  const int physLayer = blk->getInt("physLayer", PhysLayer::EPL_KINEMATIC);
  const int physMask = blk->getInt("physMask", DEFAULT_DYN_COLLISION_MASK);
  const DataBlock *collisionBlk = blk->getBlockByNameEx("collision");
  for (int i = 0; i < collisionBlk->blockCount(); ++i)
    collision.push_back(add_dynamic_collision(*collisionBlk->getBlock(i), nullptr, false, addToWorld));
  const DataBlock *collResBlk = blk->getBlockByNameEx("collisionResource", nullptr);
  if (collResBlk)
  {
    const DataBlock *collPropsBlk = collResBlk->getBlockByNameEx("props", nullptr);

    CollisionObject co;
    if (!collResBlk->getBool("normalizeCenter", false))
    {
      int addcoflags = addToWorld ? ACO_ADD_TO_WORLD : ACO_NONE;
      if (collResBlk->getBool("kinematic", false))
        addcoflags |= ACO_KINEMATIC;
      co = add_dynamic_collision_from_coll_resource(collPropsBlk, coll_res, nullptr, addcoflags, physLayer, physMask);
    }
    else
    {
      TMatrix collisionNodeInModelTm = TMatrix::IDENT;
      Point3 outCenter;
      co = add_simple_dynamic_collision_from_coll_resource(*collPropsBlk, coll_res, nullptr, collResBlk->getReal("margin", 0.0),
        collResBlk->getReal("scale", 1.0), outCenter, collisionNodeTm, collisionNodeInModelTm);

      collisionNodeTm *= inverse(collisionNodeInModelTm);

      for (int i = 0; i < collPropsBlk->paramCount(); ++i)
      {
        const int nodeId = coll_res->getNodeIndexByName(collPropsBlk->getParamName(i));
        if (nodeId >= 0)
          collisionNodes.push_back() = nodeId;
      }
    }
    collision.push_back(co);
  }
  const DataBlock *ccdBlk = blk->getBlockByNameEx("ccdSpheres");
  for (int i = 0; i < ccdBlk->paramCount(); ++i)
  {
    Point4 sph = ccdBlk->getPoint4(i);
    ccdSpheres.push_back(BSphere3(Point3::xyz(sph), sph.w));
  }
}

void PhysObj::loadFromBlk(const DataBlock *blk, const CollisionResource *coll_res, const char *, bool)
{
  loadPhysParams(blk);
  loadLimits(blk);
  loadSleepSettings(blk);
  loadSolver(blk);
  loadCollisionSettings(blk, coll_res);

  const bool inferFromCollisionResource = blk->getBool("inferFromCollision", false);
  if (inferFromCollisionResource)
  {
    // TODO: move out
    const int physLayer = blk->getInt("physLayer", dacoll::PhysLayer::EPL_KINEMATIC);
    const int physMask = blk->getInt("physMask", dacoll::DEFAULT_DYN_COLLISION_MASK);
    const float density = blk->getReal("density", -1.f);
    dacoll::PhysBodyProperties bodyProperties;
    CollisionObject co = dacoll::build_dynamic_collision_from_coll_resource(coll_res, addToWorld, physLayer, physMask, bodyProperties);
    centerOfMass = bodyProperties.centerOfMass;
    if (density > 0.f && bodyProperties.volume > 0.f)
    {
      mass = bodyProperties.volume * density;
      loadPhysParams(blk); // load again to propagate everything we've customized
    }
    const Point3 moiScale = blk->getPoint3("moiScale", Point3(1, 1, 1));
    momentOfInertia = hadamard_product(bodyProperties.momentOfInertia, moiScale);
    collision.push_back(co);
  }
}

static inline bool apply_impulse_to_ri(rendinst::RendInstDesc &ri_desc, float at_time, Point3 &velocity, float impulse,
  const Point3 &impulse_dir, const Point3 &contact_pos, float speed)
{
  if (!rendinst::isRiGenDescValid(ri_desc))
    return false;
  CachedCollisionObjectInfo *riCollisionInfo = rendinstdestr::get_or_add_cached_collision_object(ri_desc, at_time);
  if (!riCollisionInfo)
    return false;
  float destructionImpulse = riCollisionInfo->getDestructionImpulse();
  if (impulse < destructionImpulse)
    return false;
  riCollisionInfo->onImpulse(impulse, impulse_dir, contact_pos, speed);
  velocity *= (1.0f - safediv(destructionImpulse, impulse));
  return true;
}

static inline bool solve_ccd(const Point3 &from, const Point3 &to, float rad, Point3 &offset, Point3 &vel, float collision_margin,
  int phys_mat_id, dag::ConstSpan<CollisionObject> collision, dag::ConstSpan<int> ignore_objs, float energy_conservation,
  Point3 &contactPointOffset, rendinst::RendInstDesc *out_desc = nullptr, Point3 *out_ray_hit_pos = nullptr)
{
  offset.zero();
  contactPointOffset.zero();
  Point3 dir = to - from;
  float lenSq = lengthSq(dir);
  if (lenSq < 1e-5f)
    return false;

  float len = sqrtf(lenSq);
  dir *= safeinv(len);
  dacoll::ShapeQueryOutput sphQuery;
  bool res = false;
  eastl::vector<CollisionObject, framemem_allocator> ignore_coll_objs;
  if (!collision.empty() && collision[0].isValid())
  {
    ignore_coll_objs.push_back(collision[0]);
  }
  for (int objId : ignore_objs)
  {
    IPhysBase *phys = gamephys::phys_by_id(objId);
    if (phys)
    {
      dag::ConstSpan<CollisionObject> collObjs = phys->getCollisionObjects();
      ignore_coll_objs.insert(ignore_coll_objs.end(), collObjs.begin(), collObjs.end());
    }
  }
  int mask = dacoll::EPL_ALL & ~(dacoll::EPL_CHARACTER | dacoll::EPL_DEBRIS);
  if (dacoll::sphere_cast_ex(from, to, rad, sphQuery, phys_mat_id, ignore_coll_objs, nullptr, mask))
  {
    float unrestricted = (1.f - sphQuery.t) * len;
    offset = -dir * (unrestricted + collision_margin);
    contactPointOffset = sphQuery.res - (from + dir * sphQuery.t * len);
    contactPointOffset -= dir * dot(contactPointOffset, dir); // Contact point offset should not overshoot projectile position.
    // clip velocity by normal
    vel = vel - vel * sphQuery.norm * sphQuery.norm;
    if (energy_conservation < 1.f)
      vel = normalize(vel) * sqrtf(lengthSq(vel) * energy_conservation);
    res = true;
  }

  float sphereCastHitDist = len * sphQuery.t;
  float t = len;
  Point3 norm;
  if (sphereCastHitDist <= 1e-5f ||
      !dacoll::traceray_normalized(from, dir, t, nullptr, &norm, dacoll::ETF_DEFAULT, out_desc, phys_mat_id))
    return res;

  if (out_ray_hit_pos)
    *out_ray_hit_pos = from + dir * t;
  if (t <= sphereCastHitDist)
  {
    offset = dir * (t - len - collision_margin - rad);
    contactPointOffset.zero();
    // clip velocity by normal
    vel = vel - vel * norm * norm;
    if (energy_conservation < 1.f)
      vel = normalize(vel) * sqrtf(lengthSq(vel) * energy_conservation);
    res = true;
  }
  return res;
}

static void apply_limit(const Point3 &damping_mult, const Point3 &limit, bool is_absolute, Point3 &target)
{
  for (int i = 0; i < 3; ++i)
  {
    const float curVel = is_absolute ? rabs(target[i]) : target[i];
    const float dampingMult = damping_mult[i];
    const float curLimit = limit[i];
    if (dampingMult > 0.f && curVel > curLimit)
    {
      const float kv = safediv(curVel, curLimit * dampingMult) * dampingMult;
      target[i] *= safeinv(kv);
    }
  }
}

static inline void update_current_state_tick(PhysObjState &state, const PhysObjControlState &ct, float at_time, float dt,
  float time_step)
{
  state.atTick = gamephys::nearestPhysicsTickNumber(at_time + dt, time_step);
  state.lastAppliedControlsForTick = (ct.producedAtTick > 0) ? ct.producedAtTick : state.atTick - 1;
}

void PhysObj::resolveCollision(float dt, dag::ConstSpan<gamephys::CollisionContactData> contacts)
{
  TMatrix tm;
  currentState.location.toTM(tm);
  Quat orient = currentState.location.O.getQuat();

  DPoint3 invMoi = DPoint3(safeinv(momentOfInertia.x * mass), safeinv(momentOfInertia.y * mass), safeinv(momentOfInertia.z * mass));
  const double invMass = safeinv(mass);

  DPoint3 vel = dpoint3(currentState.velocity);
  DPoint3 omega = dpoint3(currentState.omega);

  daphys::ResolveContactParams contactParams;
  contactParams.useFutureContacts = useFutureContacts;
  contactParams.friction = frictionGround;
  if (limitFriction > 0.f)
  {
    contactParams.minFriction = -limitFriction;
    contactParams.maxFriction = limitFriction;
  }
  contactParams.bounce = bouncingGround;
  contactParams.minSpeedForBounce = minSpeedForBounce;
  contactParams.energyConservation = energyConservation;
  contactParams.noSleepAtTheSlopeCos = noSleepAtTheSlopeCos;
  contactParams.baumgarteFactor = baumgarteBias * safeinv(dt);
  contactParams.warmstartingFactor = warmstartingFactor;

  DPoint3 cogPos = dpoint3(tm * centerOfMass);

  Tab<gamephys::SeqImpulseInfo> collisions(framemem_ptr());
  daphys::convert_contacts_to_solver_data(cogPos, orient, contacts, collisions, safeinv(mass), invMoi, contactParams);
  daphys::energy_conservation_vel_patch(collisions, vel, omega, contactParams);
  daphys::apply_cached_contacts(cogPos, orient, vel, omega, make_span_const(currentState.cachedContacts), collisions, invMass, invMoi,
    contactParams);
  daphys::resolve_contacts(orient, vel, omega, collisions, invMass, invMoi, contactParams, 10);

  if (warmstartingFactor > 0.f)
  {
    Tab<gamephys::CachedContact> cachedContacts(framemem_ptr());
    daphys::cache_solved_contacts(collisions, cachedContacts, MAX_CACHED_CONTACTS);
    currentState.cachedContacts.clear();
    if (!cachedContacts.empty())
      currentState.cachedContacts.insert(currentState.cachedContacts.begin(), cachedContacts.begin(), cachedContacts.end());
  }
  if (erp > 0.f) // skip penetration if we don't have any erp at all
    daphys::resolve_penetration(cogPos, orient, contacts, invMass, invMoi, dt, useFutureContacts, 10, linearSlop, erp);

  DPoint3 pos = cogPos - dpoint3(orient * centerOfMass);

  currentState.velocity = Point3::xyz(vel);
  currentState.omega = Point3::xyz(omega);

  currentState.location.P = pos;
  currentState.location.O.setQuat(orient);
}

void PhysObj::updatePhys(float at_time, float dt, bool)
{
  if (skipUpdateOnSleep && currentState.isSleep)
    if (sleepUpdateFrequency > 0 ? (currentState.atTick % sleepUpdateFrequency) != 0 : true) // sometimes we don't want to skip all
                                                                                             // updates, but like update 1/10 for
                                                                                             // instance
    {
      update_current_state_tick(currentState, appliedCT, at_time, dt, timeStep);
      return;
    }

  if (shouldFallThroughGround)
  {
    currentState.velocity += Point3(0.f, -gamephys::atmosphere::g(), 0.f) * dt;
    currentState.location.P += currentState.velocity * dt;
    update_current_state_tick(currentState, appliedCT, at_time, dt, timeStep);
    return;
  }

  const int prevStep = dacoll::set_hmap_step(1);
  FINALLY([prevStep]() { dacoll::set_hmap_step(prevStep); });

  TMatrix tm;
  currentState.location.toTM(tm);
  Tab<gamephys::CollisionContactData> contacts(framemem_ptr());
  if (currentState.ignoreGameObjsUntilTime < 0.f)
    currentState.ignoreGameObjsUntilTime = ignoreGameObjsTime > 0.0f ? at_time + ignoreGameObjsTime : 0.0f;

  hasGroundCollisionPoint = false;
  hasFrtCollision = false;
  hasRiDestroyingCollision = false;

  float speed = length(currentState.velocity);
  float linearImpulse = objDestroyMass * speed;
  Point3 impulseDir = currentState.velocity * safeinv(speed);

  for (CollisionObject &co : collision)
    dacoll::set_collision_object_tm(co, tm);

  if (EASTL_LIKELY(!ignoreCollision))
    for (CollisionObject &co : collision)
    {
      if (dacoll::test_collision_frt(co, contacts, physMatId))
      {
        frtCollisionNormal = contacts[0].wnormB;
        hasFrtCollision = true;
      }
      dacoll::test_collision_ri(co, BBox3(ZERO<Point3>(), 1.f), contacts, true /*collInfo*/, at_time, nullptr, physMatId);

      for (int i = 0; i < contacts.size(); ++i)
      {
        if (!contacts[i].objectInfo)
          continue;
        float destructionImpulse = contacts[i].objectInfo->getDestructionImpulse();
        if (linearImpulse < destructionImpulse)
          continue;
        contacts[i].objectInfo->onImpulse(linearImpulse, impulseDir, contacts[i].wpos, speed);
        currentState.velocity *= (1.0f - safediv(destructionImpulse, linearImpulse));
        gamephys::remove_contact(contacts, i--);
        hasRiDestroyingCollision = true;
      }

      int prevCount = contacts.size();
      dacoll::test_collision_lmesh(co, tm, 1.f, -1, contacts, physMatId);
      if (contacts.size() > prevCount)
      {
        hasGroundCollisionPoint = true;
        groundCollisionPoint = contacts[prevCount].wpos;
      }
    }

  bool onlySupportedFromBelow = !contacts.empty();
  for (const auto &c : contacts)
    onlySupportedFromBelow &= c.wnormB.y > noSleepAtTheSlopeCos;

  if (useMovementDamping && lengthSq(currentState.velocity) < movementDampingThreshold && onlySupportedFromBelow)
    currentState.velocity.zero();
  else
    currentState.velocity += currentState.gravDirection * gamephys::atmosphere::g() * gravityMult * dt;

  if (shouldTraceGround)
  {
    const float groundSlop = 0.05f;
    float tGround = boundingRadius + 2.f * groundSlop + rabs(currentState.velocity.y) * dt;
    if (dacoll::traceray_normalized_lmesh(tm.getcol(3), Point3(0.f, -1.f, 0.f), tGround, nullptr, nullptr))
    {
      if (tGround < boundingRadius + groundSlop)
      {
        gamephys::CollisionContactData &c = contacts.push_back();
        c.wpos = tm.getcol(3) + Point3(0.f, -tGround, 0.f);
        c.wposB = ZERO<Point3>();
        c.wnormB = Point3(0.f, 1.f, 0.f);
        c.posA = ZERO<Point3>();
        c.posB = ZERO<Point3>();
        c.depth = tGround - boundingRadius + groundSlop;
        c.userPtrA = nullptr;
        c.userPtrB = nullptr;
        c.matId = -1;
        c.objectInfo = nullptr;

        hasGroundCollisionPoint = true;
        groundCollisionPoint = c.wpos;
      }
      else
      {
        const float deltaPos = currentState.velocity.y * dt;
        if (tGround + deltaPos < boundingRadius + groundSlop)
        {
          const float maxVel = (boundingRadius + groundSlop - tGround) * safeinv(dt);
          const float kv = safediv(currentState.velocity.y, maxVel) * 0.8f;
          currentState.velocity.y *= safeinv(kv);
        }
      }
    }
  }

  apply_limit(velocityLimitDampingMult, velocityLimit, isVelocityLimitAbsolute, currentState.velocity);
  apply_limit(omegaLimitDampingMult, omegaLimit, isOmegaLimitAbsolute, currentState.omega);

  if (useMovementDamping && !contacts.empty())
  {
    currentState.omega *= omegaMovementDamping;
    for (int i = 0; i < 3; ++i)
      if (fabsf(currentState.omega[i]) < omegaMovementDampingThreshold)
        currentState.omega[i] = 0.f;
  }

  currentState.velocity *= 1.0f / (1.0f + dt * linearDamping);
  currentState.omega *= 1.0f / (1.0f + dt * angularDamping);
  if (currentState.velocity.lengthSq() + currentState.omega.lengthSq() < 1e-6) // if zero
  {
    currentState.sleepTimer += dt;
    if (currentState.sleepTimer > sleepDelay)
      putToSleep(); // zero-out velocity/omega as well to avoid denomals
  }

  G_ASSERT(!check_nan(currentState.addForce));
  G_ASSERT(!check_nan(currentState.addMoment));

  if (float g = gamephys::atmosphere::g())
  {
    float force_len = length(currentState.addForce);
    if (force_len > 50.f * g * mass)
      currentState.addForce *= 50.f * g * mass / force_len;
  }

  Quat orient = currentState.location.O.getQuat();
  DPoint3 invMoi = DPoint3(safeinv(momentOfInertia.x * mass), safeinv(momentOfInertia.y * mass), safeinv(momentOfInertia.z * mass));

  currentState.velocity += orient * (currentState.addForce * safeinv(mass) * dt);

  currentState.addMoment.x *= invMoi.x;
  currentState.addMoment.y *= invMoi.y;
  currentState.addMoment.z *= invMoi.z;

  currentState.omega += currentState.addMoment * dt;

  currentState.addForce.zero();
  currentState.addMoment.zero();

  if (currentState.logCCD)
  {
    clear_and_shrink(contactsLog);
    for (const gamephys::CollisionContactData &coll : contacts)
      contactsLog.push_back(coll);
  }

  gamephys::Loc prevLoc = currentState.location;

  resolveCollision(dt, contacts);

  Point3 orientationInc = currentState.omega * dt;
  Quat quatInc = Quat(orientationInc, length(orientationInc));

  currentState.hadContact = !contacts.empty();
  Point3 contactPointOffset = ZERO<Point3>();
  Point3 constrainedVelocity = currentState.velocity;
  if (lengthSq(currentState.velocity) > 1e-5f)
  {
    Point3 ccdHitPos;
    rendinst::RendInstDesc ri_desc;
    dag::ConstSpan<int> ignoreObjsSlice;
    if ((currentState.ignoreGameObjsUntilTime == 0.0f) || (at_time < currentState.ignoreGameObjsUntilTime))
      ignoreObjsSlice = ignoreGameObjs;
    for (const BSphere3 &ccd : ccdSpheres)
    {
      dacoll::ShapeQueryOutput sphQuery;
      Point3 pos = ccd.c;
      Point3 posTo = ccd.c;
      prevLoc.transform(pos);
      currentState.location.transform(posTo);
      Point3 offset;
      Point3 tempCpOffset;
      bool ok = solve_ccd(pos, posTo, ccd.r, offset, constrainedVelocity, ccd.r * 0.3f, physMatId, collision, ignoreObjsSlice,
        energyConservation, tempCpOffset, &ri_desc, &ccdHitPos);
      currentState.hadContact |= ok;
      if (ok)
        contactPointOffset = tempCpOffset + (pos - prevLoc.P);
      hasRiDestroyingCollision |=
        apply_impulse_to_ri(ri_desc, at_time, currentState.velocity, linearImpulse, impulseDir, ccdHitPos, speed);
      ri_desc.invalidate();
      if (currentState.logCCD)
        ccdLog.push_back(CCDCheck(pos, posTo, offset));
      currentState.location.P += dpoint3(offset);

      pos = ccd.c;
      currentState.location.transform(pos);
      gamephys::Loc nextState = currentState.location;
      nextState.P += constrainedVelocity * dt;
      nextState.O.setQuat(normalize(nextState.O.getQuat() * quatInc));

      posTo = ccd.c;
      nextState.transform(posTo);
      ok = solve_ccd(pos, posTo, ccd.r, offset, constrainedVelocity, ccd.r * 0.3f, physMatId, collision, ignoreObjsSlice,
        energyConservation, tempCpOffset, &ri_desc, &ccdHitPos);
      currentState.hadContact |= ok;
      if (ok)
        contactPointOffset = tempCpOffset + (pos - currentState.location.P);
      hasRiDestroyingCollision |=
        apply_impulse_to_ri(ri_desc, at_time, currentState.velocity, linearImpulse, impulseDir, ccdHitPos, speed);
      ri_desc.invalidate();
      if (currentState.logCCD)
        ccdLog.push_back(CCDCheck(pos, posTo, offset));
      currentState.location.P += dpoint3(offset);
    }
  }
  if (currentState.hadContact)
  {
    currentState.contactPoint = currentState.location.P + dpoint3(currentState.velocity * dt + contactPointOffset);
    currentState.velocity = constrainedVelocity;
  }
  currentState.location.P += constrainedVelocity * dt;
  DPoint3 centerOfMassInWorldBefore = dpoint3(currentState.location.O.getQuat() * centerOfMass);
  currentState.location.O.setQuat(normalize(currentState.location.O.getQuat() * quatInc));
  DPoint3 centerOfMassInWorldAfter = dpoint3(currentState.location.O.getQuat() * centerOfMass);
  currentState.location.P += centerOfMassInWorldBefore - centerOfMassInWorldAfter;

  update_current_state_tick(currentState, appliedCT, at_time, dt, timeStep);
}

void PhysObj::applyOffset(const Point3 &offset) { currentState.location.P += dpoint3(offset); }

void PhysObj::reset() { currentState.reset(); }

void PhysObj::updatePhysInWorld(const TMatrix &tm)
{
  if (!addToWorld)
    return;
  for (const CollisionObject &co : collision)
    if (co)
      dacoll::set_obj_motion(co, tm, currentState.velocity, currentState.omega);
}

void PhysObj::drawDebug()
{
  E3DCOLOR noCollision = E3DCOLOR_MAKE(0, 255, 0, 255);
  E3DCOLOR haveCollision = E3DCOLOR_MAKE(255, 0, 0, 255);
  for (const CCDCheck &logEntry : ccdLog)
  {
    draw_debug_line_buffered(logEntry.from, logEntry.to, logEntry.res ? haveCollision : noCollision);
    if (logEntry.res)
      draw_debug_sph(BSphere3(logEntry.to + logEntry.offset, 0.1f), haveCollision);
  }

  for (const gamephys::CollisionContactData &contact : contactsLog)
  {
    draw_debug_sph(BSphere3(Point3::xyz(contact.wpos - contact.wnormB * contact.depth), max(fabsf(contact.depth), 0.01f)),
      contact.depth > 0.f ? noCollision : haveCollision);
    draw_debug_line(contact.wpos, contact.wpos + contact.wnormB);
  }

  if (currentState.logCCD) // TODO: rename it
  {
    for (const CollisionObject &co : collision)
      dacoll::draw_collision_object(co);

    const E3DCOLOR outsideCache = E3DCOLOR_MAKE(0, 255, 255, 255);
    const E3DCOLOR insideCache = E3DCOLOR_MAKE(255, 0, 255, 255);
    TMatrix tm;
    currentState.location.toTM(tm);
    Point3 cogPos = tm * centerOfMass;
    for (const gamephys::CachedContact &contact : currentState.cachedContacts)
    {
      draw_debug_sph(BSphere3(contact.wpos, max(fabsf(contact.depth), 0.01f)), contact.depth > 0.f ? outsideCache : insideCache);
      draw_debug_line(contact.wpos, contact.wpos + contact.wnorm * 0.2f, insideCache);
      draw_debug_sph(BSphere3(cogPos + currentState.location.O.getQuat() * contact.localPos, 0.01f), E3DCOLOR_MAKE(255, 0, 0, 255));
    }
  }
}

static void apply_force(const Point3 &force, const Point3 &arm, const Point3 &center_of_gravity, Point3 &outForce, Point3 &outMoment)
{
  G_ASSERT(!check_nan(force));
  G_ASSERT(!check_nan(arm));
  outForce += force;
  outMoment += (arm - center_of_gravity) % force;
}

void PhysObj::addForce(const Point3 &arm, const Point3 &force)
{
  apply_force(force, arm, getCenterOfMass(), currentState.addForce, currentState.addMoment);
  wakeUp();
}

void PhysObj::addSoundShockImpulse(float val) { soundShockImpulse += val; }
float PhysObj::getSoundShockImpulse() const { return soundShockImpulse; }

TMatrix PhysObj::getCollisionObjectsMatrix() const { return currentState.location.makeTM(); }

bool PhysObj::isCollisionValid() const
{
  if (collision.empty())
    return false;

  bool result = true;
  for (const auto &col : collision)
    if (!col.isValid())
    {
      result = false;
      break;
    }
  return result;
}
