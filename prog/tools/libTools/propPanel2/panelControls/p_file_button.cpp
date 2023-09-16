// Copyright 2023 by Gaijin Games KFT, All rights reserved.

#include "p_file_button.h"
#include "../c_constants.h"
#include <winGuiWrapper/wgw_dialogs.h>

CFileButton::CFileButton(ControlEventHandler *event_handler, PropertyContainerControlBase *parent, int id, int x, int y, int w,
  const char caption[]) :

  BasicPropertyControl(id, event_handler, parent, x, y, w, DEFAULT_CONTROL_HEIGHT + DEFAULT_BUTTON_HEIGHT),

  mCaption(this, parent->getWindow(), x, y, w, DEFAULT_CONTROL_HEIGHT),

  mFileButton(this, parent->getWindow(), x, y + DEFAULT_CONTROL_HEIGHT, w - 2 * DEFAULT_CONTROL_HEIGHT - DEFAULT_CONTROLS_INTERVAL,
    DEFAULT_BUTTON_HEIGHT),

  mClearButton(this, parent->getWindow(), x + mFileButton.getWidth() + DEFAULT_CONTROLS_INTERVAL, y + DEFAULT_CONTROL_HEIGHT,
    2 * DEFAULT_CONTROL_HEIGHT, DEFAULT_BUTTON_HEIGHT),

  mValue("")
{
  mCaption.setTextValue(caption);
  mFileButton.setTextValue("none");
  mClearButton.setTextValue("x");
  strcpy(mMasks, "All|*.*||");
  initTooltip(&mFileButton);
}


PropertyContainerControlBase *CFileButton::createDefault(int id, PropertyContainerControlBase *parent, const char caption[],
  bool new_line)
{
  parent->createFileButton(id, caption, "", true, new_line);
  return NULL;
}


void CFileButton::setEnabled(bool enabled)
{
  mCaption.setEnabled(enabled);
  mFileButton.setEnabled(enabled);
  mClearButton.setEnabled(enabled);
}


void CFileButton::reset()
{
  this->setTextValue("");
  PropertyControlBase::reset();
}


void CFileButton::setWidth(unsigned w)
{
  int minw = 2 * DEFAULT_CONTROL_HEIGHT + DEFAULT_CONTROLS_INTERVAL;
  w = (w < minw) ? minw : w;

  PropertyControlBase::setWidth(w);

  mCaption.resizeWindow(w, mCaption.getHeight());
  mFileButton.resizeWindow(w - 2 * DEFAULT_CONTROL_HEIGHT - DEFAULT_CONTROLS_INTERVAL, mFileButton.getHeight());
  mClearButton.resizeWindow(2 * DEFAULT_CONTROL_HEIGHT, mClearButton.getHeight());

  this->moveTo(this->getX(), this->getY());
}


void CFileButton::setTextValue(const char value[])
{
  mValue = value;
  if (mValue != "")
    mFileButton.setTextValue(value);
  else
    mFileButton.setTextValue("none");
}


void CFileButton::setCaptionValue(const char value[]) { mCaption.setTextValue(value); }


void CFileButton::setStringsValue(const Tab<String> &vals)
{
  int c = vals.size();
  strcpy(mMasks, "\0");

  for (int i = 0; (i < c) && (strlen(mMasks) + vals[i].size() < FILTER_STRING_SIZE - 2); ++i)
  {
    strcat(mMasks, vals[i]);
    strcat(mMasks, "|");
  }

  strcat(mMasks, "|");
}


int CFileButton::getTextValue(char *buffer, int buflen) const
{
  if (mValue.size() < buflen)
  {
    strcpy(buffer, mValue);
    return i_strlen(buffer);
  }

  return 0;
}


void CFileButton::moveTo(int x, int y)
{
  PropertyControlBase::moveTo(x, y);

  mCaption.moveWindow(x, y);
  mFileButton.moveWindow(x, y + DEFAULT_CONTROL_HEIGHT);
  mClearButton.moveWindow(x + mFileButton.getWidth() + DEFAULT_CONTROLS_INTERVAL, y + DEFAULT_CONTROL_HEIGHT);
}


void CFileButton::onWcClick(WindowBase *source)
{
  if (source == &mFileButton)
  {
    String result = wingw::file_open_dlg(this->getRootParent()->getWindowHandle(), "Select file...", mMasks, mValue);
    if (!result.empty())
    {
      setTextValue(result.str());
      PropertyControlBase::onWcChange(source);
    }
  }

  if (source == &mClearButton)
  {
    setTextValue("");
    PropertyControlBase::onWcChange(source);
  }
}
