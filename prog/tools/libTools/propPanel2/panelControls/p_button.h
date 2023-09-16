#pragma once

#include "p_base.h"
#include "../windowControls/w_simple_controls.h"
#include <propPanel2/c_panel_base.h>


class CButton : public BasicPropertyControl
{
public:
  CButton(ControlEventHandler *event_handler, PropertyContainerControlBase *parent, int id, int x, int y, int w, const char caption[]);

  static PropertyContainerControlBase *createDefault(int id, PropertyContainerControlBase *parent, const char caption[],
    bool new_line = true);

  unsigned getTypeMaskForSet() const { return CONTROL_CAPTION | CONTROL_DATA_TYPE_STRING; }
  unsigned getTypeMaskForGet() const { return 0; }

  void setCaptionValue(const char value[]);
  void setTextValue(const char value[]);

  void setEnabled(bool enabled);
  void setWidth(unsigned w);
  void setFocus();
  void moveTo(int x, int y);

private:
  WButton mButton;
};
