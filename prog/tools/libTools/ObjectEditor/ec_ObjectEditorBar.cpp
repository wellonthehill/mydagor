#include <libTools/util/strUtil.h>

#include <EditorCore/ec_IEditorCore.h>
#include <EditorCore/ec_ObjectEditor.h>
#include <EditorCore/ec_rendEdObject.h>
#include <EditorCore/ec_cm.h>

#include <debug/dag_debug.h>

enum
{
  ID_NAME = 10000,
  ID_COUNT,
  ID_CID,
  ID_CID_REFILL,
};

template <class T>
inline dag::Span<T *> mk_slice(PtrTab<T> &t)
{
  return make_span<T *>(reinterpret_cast<T **>(t.data()), t.size());
}

ObjectEditorPropPanelBar::ObjectEditorPropPanelBar(ObjectEditor *obj_ed, void *hwnd, const char *caption) :
  objEd(obj_ed), objects(midmem)
{
  IWndManager *manager = IEditorCoreEngine::get()->getWndManager();
  G_ASSERT(manager && "ObjectEditorPropPanelBar ctor: WndManager is NULL!");
  manager->setCaption(hwnd, caption);

  propPanel = IEditorCoreEngine::get()->createPropPanel(this, hwnd);
}


ObjectEditorPropPanelBar::~ObjectEditorPropPanelBar()
{
  if (objects.size())
    objects[0]->onPPClose(*propPanel, mk_slice(objects));

  IEditorCoreEngine::get()->deleteCustomPanel(propPanel);
  propPanel = NULL;
}


void ObjectEditorPropPanelBar::getObjects()
{
  objects.resize(objEd->selectedCount());

  for (int i = 0; i < objEd->selectedCount(); ++i)
    objects[i] = objEd->getSelected(i);
}


void ObjectEditorPropPanelBar::onChange(int pcb_id, PropertyContainerControlBase *panel)
{
  if (pcb_id == ID_NAME)
  {
    objEd->renameObject(objEd->getSelected(0), panel->getText(pcb_id).str());
  }
  else if (objects.size())
  {
    objEd->getUndoSystem()->begin();
    objects[0]->onPPChange(pcb_id, true, *panel, mk_slice(objects));
    objEd->getUndoSystem()->accept("Params change");
  }
}


void ObjectEditorPropPanelBar::onClick(int pcb_id, PropertyContainerControlBase *panel)
{
  if (objects.size())
  {
    objEd->getUndoSystem()->begin();
    objects[0]->onPPBtnPressed(pcb_id, *panel, mk_slice(objects));
    objEd->getUndoSystem()->accept("Params change");
  }
}


void ObjectEditorPropPanelBar::onPostEvent(int pcb_id, PropPanel2 *panel)
{
  if (pcb_id == ID_CID_REFILL)
    fillPanel();
}


void ObjectEditorPropPanelBar::refillPanel()
{
  if (propPanel)
    propPanel->setPostEvent(ID_CID_REFILL);
}


void ObjectEditorPropPanelBar::fillPanel()
{
  G_ASSERT(propPanel && "ObjectEditorPropPanelBar::fillPanel: ppanel is NULL!");

  int curScroll = propPanel->getScrollPos();

  if (objects.size() && objects[0].get() && propPanel->getById(ID_NAME))
    objects[0]->onPPClear(*propPanel, mk_slice(objects));

  clear_and_shrink(objects);

  propPanel->clear();

  propPanel->createEditBox(ID_NAME, "Name:", "", false);

  if (objEd->selectedCount())
  {
    if (objEd->selectedCount() == 1)
    {
      propPanel->setEnabledById(ID_NAME, true);
      propPanel->setText(ID_NAME, objEd->getSelected(0)->getName());
    }
    else
      propPanel->setText(ID_NAME, String(100, "%d objects selected", objEd->selectedCount()));

    getObjects();

    // propPanel->createEditInt(ID_COUNT, "Num objects:", objects.size(), false);

    if (objects.size())
    {
      dag::Span<RenderableEditableObject *> o = mk_slice(objects);
      DClassID commonClassId = objects[0]->getCommonClassId(o.data(), o.size());
      // propPanel->createEditBox(ID_CID, "Common CID:",
      //   String(32, "%08X", commonClassId.id).str(), false);
      objects[0]->fillProps(*propPanel, commonClassId, o);
    }
    else
      propPanel->setEnabledById(ID_NAME, false);
  }

  propPanel->setScrollPos(curScroll);
}


void ObjectEditorPropPanelBar::updateName(const char *name)
{
  G_ASSERT(propPanel && "ObjectEditorPropPanelBar::fillPanel: ppanel is NULL!");

  SimpleString curName(propPanel->getText(ID_NAME));
  if (curName != name)
    propPanel->setText(ID_NAME, name);
}
