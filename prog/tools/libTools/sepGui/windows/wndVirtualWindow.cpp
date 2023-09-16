// Copyright 2023 by Gaijin Games KFT, All rights reserved.

#include "../wndManager.h"
#include "wndVirtualWindow.h"
#include "wndSplitterWindow.h"

#include <windows.h>


//=============================================================================
VirtualWindow::VirtualWindow(WinManager *owner) : CascadeWindow(owner, NULL, 0, 0, 0, 0) {}


//=============================================================================
VirtualWindow::~VirtualWindow()
{
  mOwner->onVirtualWindowDeleted(this);

  del_it(mLeftWnd);
  del_it(mRightWnd);
  del_it(mSplitterWnd);
}


//=============================================================================
void VirtualWindow::refreshPos()
{
  IPoint2 leftTop, rightBottom;
  getPos(leftTop, rightBottom);
  resize(leftTop, rightBottom);
}


//=============================================================================
ClientWindow *VirtualWindow::getWindowOnPos(const IPoint2 &cur_point)
{
  ClientWindow *findedWindow = NULL;
  findedWindow = mLeftWnd->getWindowOnPos(cur_point);
  if (!findedWindow)
    findedWindow = mRightWnd->getWindowOnPos(cur_point);

  return findedWindow;
}


//=============================================================================
VirtualWindow *VirtualWindow::getVirtualWindow() const { return (VirtualWindow *)this; }


//=============================================================================
ClientWindow *VirtualWindow::getClientWindow() const { return NULL; }


//=============================================================================
void VirtualWindow::setRatio(float new_ratio) { mRatio = new_ratio; }


//=============================================================================
float VirtualWindow::getRatio() const { return mRatio; }


//=============================================================================
WindowSizeLock VirtualWindow::getSizeLock() const
{
  WindowSizeLock leftSizeLockType = mLeftWnd->getSizeLock();
  WindowSizeLock rightSizeLockType = mRightWnd->getSizeLock();

  unsigned widthLock, heightLock;
  if (isVertical())
  {
    widthLock = (leftSizeLockType & rightSizeLockType) & WSL_WIDTH;
    heightLock = (leftSizeLockType | rightSizeLockType) & WSL_HEIGHT;
  }
  else
  {
    widthLock = (leftSizeLockType | rightSizeLockType) & WSL_WIDTH;
    heightLock = (leftSizeLockType & rightSizeLockType) & WSL_HEIGHT;
  }

  return (WindowSizeLock)(heightLock | widthLock);
}


//=============================================================================
bool VirtualWindow::getMinSize(int &min_w, int &min_h)
{
  const int WINS_COUNT = 3;
  CascadeWindow *wins[WINS_COUNT] = {mLeftWnd, mSplitterWnd, mRightWnd};

  min_w = 0;
  min_h = 0;
  int minW, minH;
  bool isVertical = mSplitterWnd->getIsVertical();
  for (int i = 0; i < WINS_COUNT; ++i)
  {
    wins[i]->getMinSize(minW, minH);

    if (isVertical)
    {
      min_w += minW;
      if (min_h < minH)
        min_h = minH;
    }
    else
    {
      min_h += minH;
      if (min_w < minW)
        min_w = minW;
    }
  }

  if (isVertical)
    min_w += 2;
  else
    min_h += 2;

  return WSL_NONE | getSizeLock();
}


//=============================================================================
void VirtualWindow::resize(const IPoint2 &left_top, const IPoint2 &right_bottom)
{
  mLeftTop = left_top;
  mRightBottom = right_bottom;

  int w = right_bottom.x - left_top.x;
  int h = right_bottom.y - left_top.y;

  bool vertical = mSplitterWnd->getIsVertical();

  int spltrMinSz[2];
  int leftMinSz[2];
  int rightMinSz[2];

  mSplitterWnd->getMinSize(spltrMinSz[0], spltrMinSz[1]);
  bool leftRes = mLeftWnd->getMinSize(leftMinSz[0], leftMinSz[1]);
  bool rightRes = mRightWnd->getMinSize(rightMinSz[0], rightMinSz[1]);

  int wOffset = SPLITTER_THICKNESS + SPLITTER_SPACE * 2;
  int size = (vertical ? w : h);
  int i = vertical ? 0 : 1;

  int center = (size - wOffset) * mRatio + SPLITTER_SPACE;
  if (leftRes)
  {
    if ((vertical && (WSL_WIDTH & mLeftWnd->getSizeLock())) || (!vertical && (WSL_HEIGHT & mLeftWnd->getSizeLock())))
    {
      mRatio = (float)leftMinSz[i] / (size - wOffset);
      center = leftMinSz[i] + SPLITTER_SPACE;
    }
  }
  if (rightRes)
  {
    if ((vertical && (WSL_WIDTH & mRightWnd->getSizeLock())) || (!vertical && (WSL_HEIGHT & mRightWnd->getSizeLock())))
    {
      mRatio = (float)(size - wOffset - rightMinSz[i]) / (size - wOffset);
      center = size - rightMinSz[i] + SPLITTER_THICKNESS + SPLITTER_SPACE;
    }
  }

  int min = leftMinSz[i] + SPLITTER_SPACE;
  int max = vertical ? w : h;
  max -= rightMinSz[i] + SPLITTER_SPACE + spltrMinSz[i];

  center = center < min ? min : center;
  center = center > max ? max : center;

  IPoint2 splitterCuts[2] = {right_bottom, left_top};

  if (vertical)
  {
    splitterCuts[0].x = left_top.x + center - SPLITTER_SPACE;
    splitterCuts[1].x = left_top.x + center + SPLITTER_THICKNESS + SPLITTER_SPACE;
  }
  else
  {
    splitterCuts[0].y = left_top.y + center - SPLITTER_SPACE;
    splitterCuts[1].y = left_top.y + center + SPLITTER_THICKNESS + SPLITTER_SPACE;
  }

  IPoint2 splitterPos1, splitterPos2;
  splitterPos1.x = vertical ? splitterCuts[0].x + SPLITTER_SPACE : left_top.x;
  splitterPos1.y = !vertical ? splitterCuts[0].y + SPLITTER_SPACE : left_top.y;
  splitterPos2.x = vertical ? splitterCuts[1].x - SPLITTER_SPACE : right_bottom.x;
  splitterPos2.y = !vertical ? splitterCuts[1].y - SPLITTER_SPACE : right_bottom.y;

  mLeftWnd->resize(left_top, splitterCuts[0]);
  mSplitterWnd->resize(splitterPos1, splitterPos2);
  mRightWnd->resize(splitterCuts[1], right_bottom);
};


//=============================================================================
void VirtualWindow::getPos(IPoint2 &left_top, IPoint2 &right_bottom) const
{
  left_top = mLeftTop;
  right_bottom = mRightBottom;
}


//=============================================================================
void VirtualWindow::deleteSplitter(bool delete_right)
{
  CascadeWindow *window = delete_right ? getSecond() : getFirst();
  mOwner->deleteWindow(window);
}


//*****************************************************************************
//=============================================================================
void VirtualWindow::setWindows(CascadeWindow *one, CascadeWindow *two, SplitterWindow *splitter, float ratio, const IPoint2 &p1,
  const IPoint2 &p2)
{
  G_ASSERT(one && two && splitter && "VirtualWindow::setWindows(): NULL pointer was passed!");

  setFirst(one);
  setSecond(two);

  mSplitterWnd = splitter;
  mSplitterWnd->setParent(this);

  mRatio = ratio;

  mLeftTop = p1;
  mRightBottom = p2;
}


//=============================================================================
void VirtualWindow::setFirst(CascadeWindow *one)
{
  mLeftWnd = one;
  if (one)
    one->setParent(this);
}


//=============================================================================
CascadeWindow *VirtualWindow::getFirst() const { return mLeftWnd; }


//=============================================================================
void VirtualWindow::setSecond(CascadeWindow *two)
{
  mRightWnd = two;
  if (two)
    two->setParent(this);
}


//=============================================================================
CascadeWindow *VirtualWindow::getSecond() const { return mRightWnd; }


//=============================================================================
bool VirtualWindow::isVertical() const
{
  G_ASSERT(mSplitterWnd && "VirtualWindow::isVertical(): Splitter is NULL!");

  return mSplitterWnd->getIsVertical();
}
