// Copyright 2023 by Gaijin Games KFT, All rights reserved.

#include "p_gradient_plot.h"
#include "../c_constants.h"

CGradientPlot::CGradientPlot(ControlEventHandler *event_handler, PropertyContainerControlBase *parent, int id, int x, int y,
  hdpi::Px w, hdpi::Px h, const char caption[]) :
  BasicPropertyControl(id, event_handler, parent, x, y, w, h + _pxScaled(DEFAULT_CONTROL_HEIGHT)),
  mCaption(this, parent->getWindow(), x, y, _px(w), _pxS(DEFAULT_CONTROL_HEIGHT)),
  mPlot(this, parent->getWindow(), x, y + mCaption.getHeight(), _px(w), _px(h))
{
  hasCaption = strlen(caption) > 0;

  if (hasCaption)
  {
    mCaption.setTextValue(caption);
    mH = mCaption.getHeight() + mPlot.getHeight();
  }
  else
  {
    mCaption.hide();
    mH = mPlot.getHeight();
    this->moveTo(x, y);
  }
  initTooltip(&mPlot);
}

PropertyContainerControlBase *CGradientPlot::createDefault(int id, PropertyContainerControlBase *parent, const char caption[],
  bool new_line)
{
  parent->createGradientPlot(id, caption, _pxScaled(GRADIENT_HEIGHT), true, new_line);
  return NULL;
}


void CGradientPlot::setColorValue(E3DCOLOR value) { mPlot.setColorValue(value); }

void CGradientPlot::setPoint3Value(Point3 value) { mPlot.setColorFValue(value); }

void CGradientPlot::setIntValue(int value) { mPlot.setMode(value); }

E3DCOLOR CGradientPlot::getColorValue() const { return mPlot.getColorValue(); }

Point3 CGradientPlot::getPoint3Value() const { return mPlot.getColorFValue(); }

int CGradientPlot::getIntValue() const { return mPlot.getMode(); }


void CGradientPlot::setWidth(hdpi::Px w)
{
  PropertyControlBase::setWidth(w);

  mPlot.resizeWindow(_px(w), mPlot.getHeight());
  mCaption.resizeWindow(_px(w), mCaption.getHeight());
}

void CGradientPlot::reset()
{
  mPlot.reset();
  mPlot.refresh(false);
}

void CGradientPlot::moveTo(int x, int y)
{
  PropertyControlBase::moveTo(x, y);

  mCaption.moveWindow(x, y);
  mPlot.moveWindow(x, (hasCaption) ? y + mCaption.getHeight() : y);
}

void CGradientPlot::onWcChange(WindowBase *source)
{
  mPlot.refresh(false);
  PropertyControlBase::onWcChange(source);
}
