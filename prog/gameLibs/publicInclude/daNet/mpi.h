//
// Dagor Engine 6.5 - Game Libraries
// Copyright (C) 2023  Gaijin Games KFT.  All rights reserved
// (for conditions of use see prog/license.txt)
//
#pragma once

#include <daNet/idFieldSerializer.h>
#include <util/dag_stdint.h>
#include "bitStream.h"
#include <memory/dag_framemem.h>

namespace mpi // message passing interface
{
class IObject;
class Message;

typedef uint16_t ObjectID;
typedef uint16_t MessageID;
typedef uint8_t SystemID;

typedef IObject *(*object_dispatcher)(ObjectID);

#define INVALID_OBJECT_ID  ObjectID(-1)
#define INVALID_MESSAGE_ID MessageID(-1)
#define INVALID_SYSTEM_ID  SystemID(-1)

enum TransmissionType
{
  NO_TRANSMISSION,
  RELIABLE_ORDERED_TRANSMISSION,
  RELIABLE_UNORDERED_TRANSMISSION,
  UNRELIABLE_TRANSMISSION
};

struct IMessageListener // subsytem that handles messages (typically - local, multiplayer, replay...)
{
  IMessageListener *next;
  virtual void receiveMpiMessage(const Message *msg, SystemID receiver) = 0; // process message
};

class IObject // base class for objects that handle messages
{
protected:
  ObjectID mpiObjectUID;

public:
  virtual ~IObject() {}
  IObject(ObjectID uid = INVALID_OBJECT_ID) : mpiObjectUID(uid) {}
  ObjectID getUID() const { return mpiObjectUID; }
  virtual Message *dispatchMpiMessage(MessageID mid) = 0; // construct message instance by message id
  virtual void applyMpiMessage(const Message *m) = 0;     // execute message
};

#define MPI_HEADER_SIZE (sizeof(mpi::ObjectID) + sizeof(mpi::MessageID) + sizeof(mpi::SystemID))
#define SET_TRANSMISSION_TYPE(tt)                               \
  virtual mpi::TransmissionType defaultTransmissionType() const \
  {                                                             \
    return tt;                                                  \
  }

class Message // base class for all messages
{
public:
  mpi::IObject *obj; // recepient of this message, can't be NULL
  IMemAlloc *allocator;
  MessageID id;             // identificator of this message
  SystemID senderId;        // system that sended this message (relevant only for multiplayer messages)
  danet::BitStream payload; // serialized parameters for this message

  void setFieldSize(BitSize_t sz) { idFieldSerializer.setFieldSize(sz); }
#if DAGOR_DBGLEVEL > 0
  void checkFieldSize(int index, BitSize_t sz) const { return idFieldSerializer.checkFieldSize(index, sz); }
#endif
protected:
  void writeFieldsSize() { idFieldSerializer.writeFieldsSize(payload); }
  void skipReadingField(int index) const { idFieldSerializer.skipReadingField(index, payload); }
  uint32_t readFieldsSizeAndFlag() { return idFieldSerializer.readFieldsSizeAndFlag(payload); }

private:
  danet::IdFieldSerializer32 idFieldSerializer;

public:
  Message(IObject *o, MessageID mid, IMemAlloc *allocator_ = DANET_MEM) :
    obj(o), allocator(allocator_), id(mid), senderId(INVALID_SYSTEM_ID), payload(allocator), idFieldSerializer()
  {}
  virtual ~Message() {}

  Message(const Message &rhs) :
    obj(rhs.obj),
    allocator(DANET_MEM),
    id(rhs.id),
    senderId(rhs.senderId),
    payload(rhs.payload),
    idFieldSerializer(rhs.idFieldSerializer)
  {}
  Message &operator=(const Message &rhs)
  {
    if (this == &rhs)
      return *this;
    obj = rhs.obj;
    id = rhs.id;
    senderId = rhs.senderId;
    payload.~BitStream();
    new (&payload, _NEW_INPLACE) danet::BitStream(rhs.payload.GetData(), rhs.payload.GetNumberOfBytesUsed(), true);
    allocator = DANET_MEM;
    idFieldSerializer = rhs.idFieldSerializer;
    return *this;
  }

  void destroy()
  {
    this->~Message();
    allocator->free(this);
  }
  void serialize(danet::BitStream &bs) const // full serialize of this message
  {
    bs.Write(obj->getUID());
    bs.Write(id);
    bs.Write((const char *)payload.GetData(), payload.GetNumberOfBytesUsed());
  }
  void apply() const { obj->applyMpiMessage(this); } // actually execute this message

  virtual const char *getDebugMpiName() const { return ""; }

  virtual bool isApplicable(const IMessageListener *) const { return true; }; // is this message relevant for this listener?
  virtual bool isNeedReception() const { return true; };                      // do we need receive this messags?
  virtual bool isNeedTransmission() const { return true; }                    // do we need send this message to remote system(s)?
  SET_TRANSMISSION_TYPE(RELIABLE_ORDERED_TRANSMISSION) // by default reliable ordered transmission is set, so you can redefine that in
                                                       // children classes
  virtual TransmissionType isNeedTransmissionTo(SystemID /*recipient_id*/) const // do we need and how we need to send this message to
                                                                                 // particular remote system?
  {
    return RELIABLE_ORDERED_TRANSMISSION;
  }
  virtual int getChannelId() const { return 0; }
  virtual bool isNeedProcessing() const { return true; } // do we need apply this message?

  // deserialize from/serialize parameters to 'payload' bitStream (if exist any)
  virtual void writePayload() {}
  virtual bool readPayload() { return true; }
};

Message *dispatch(const danet::BitStream &bs, bool copy_payload = false); // assemble message by BitStream. Note : message should be
                                                                          // destroyed after use (i.e. msg->destroy())
void sendto(Message *m, SystemID receiver);                               // send message, also apply if need to
inline void send(Message *m) { sendto(m, INVALID_SYSTEM_ID); }
void register_listener(IMessageListener *l);           // register listener for message handling
void unregister_listener(IMessageListener *l);         // invert operation
void register_object_dispatcher(object_dispatcher od); // register function for dispatch objects
IObject *dispatch_object(mpi::ObjectID oid);

template <typename T>
inline void write_type_proxy(danet::BitStream &bs, const T &t)
{
  bs.Write(t);
}

inline void write_type_proxy(danet::BitStream &bs, const IObject *t) { bs.Write(t ? t->getUID() : INVALID_OBJECT_ID); }
template <typename T>
inline bool read_type_proxy(const danet::BitStream &bs, T &t)
{
  return bs.Read(t);
}
inline bool read_type_proxy(const danet::BitStream &bs, IObject *&t)
{
  ObjectID oid = INVALID_OBJECT_ID;
  if (bs.Read(oid))
  {
    t = dispatch_object(oid);
    return true;
  }
  return false;
}
}; // namespace mpi

#define MPI_REMAP_TYPE_AS(type, rtype)                              \
  inline void write_type_proxy(danet::BitStream &bs, const type &t) \
  {                                                                 \
    bs.Write((rtype)t);                                             \
  }                                                                 \
  inline bool read_type_proxy(const danet::BitStream &bs, type &t)  \
  {                                                                 \
    rtype val;                                                      \
    if (!bs.Read(val))                                              \
      return false;                                                 \
    t = (type)val;                                                  \
    return true;                                                    \
  }
