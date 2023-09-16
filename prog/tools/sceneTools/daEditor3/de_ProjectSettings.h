#ifndef __GAIJIN_DE_PROJECT_SETTINGS_DLG__
#define __GAIJIN_DE_PROJECT_SETTINGS_DLG__
#pragma once

#include <propPanel2/comWnd/dialog_window.h>

#include <generic/dag_tab.h>
#include <math/dag_math3d.h>
#include <math/dag_e3dColor.h>


class FileNameEdit;
class DagorEdAppWindow;
class TrackBar;
class RealTrackBar;
class VectorEdit;

class PsExternalTab;
class PsLightTab;
class MiscTab;
class PsCollisionTab;

//==============================================================================
// ProjectSettingsDlg
//==============================================================================
class ProjectSettingsDlg : public CDialogWindow
{
public:
  ProjectSettingsDlg(void *phandle, bool &use_dir_light);

private:
  virtual bool onOk();
  virtual void onChange(int pcb_id, PropPanel2 *panel);
  virtual long onChanging(int pcb_id, PropPanel2 *panel);
  virtual void onClick(int pcb_id, PropPanel2 *panel);

  PropertyContainerControlBase *mTabPage;

  PsExternalTab *externalTab;
  PsLightTab *lightTab;
  MiscTab *miscTab;
  PsCollisionTab *collisionTab;
};


//==============================================================================
// PsExternalTab
//==============================================================================
class PsExternalTab
{
public:
  PsExternalTab(PropertyContainerControlBase *tab_page);
  virtual ~PsExternalTab();

  int handleEvent(int pcb_id, PropPanel2 *panel);
  bool onOkPressed();
  void fixPath(int pcb_id);

private:
  PropertyContainerControlBase *mTabPage;
  Tab<String> oldVals;
  bool nowEdit;
};


//==============================================================================
// PsLightTab
//==============================================================================
enum
{
  USE_RADIO_GROUP = 200,
  USE_DIR_RADIO_BUTTON,
  USE_LIGHT_RADIO_BUTTON,
  AMBIENT_TRACK_ID,
  AMBIENT_COLOR_ID,
  DIRECT_TRACK_ID,
  DIRECT_COLOR_ID,
  ZENITH_AZIMUTH_ID,
  APPLY_BUTTON_ID,
};
class PsLightTab
{
public:
  PsLightTab(PropertyContainerControlBase *tab_page, bool &use_dir_light);
  virtual ~PsLightTab();

  inline E3DCOLOR getAmbientColor() const { return ambient; }
  inline E3DCOLOR getDirectColor() const { return direct; }

  real getAmbientMul() const;
  real getDirectMul() const;

  Point2 getLightDirection() const;

  int handleEvent(int pcb_id, PropPanel2 *panel);
  bool onOkPressed();
  void onApply();

private:
  PropertyContainerControlBase *mTabPage;
  E3DCOLOR ambient;
  E3DCOLOR direct;
  bool &useDirLight;
  bool prevUseDirLight;

  void disableControls(bool light);
};


//==============================================================================
// MiscTab
//==============================================================================
class MiscTab
{
public:
  MiscTab(PropertyContainerControlBase *tab_page);
  bool onOkPressed();

private:
  enum
  {
    TEXQUALITY_RADIO_GRP_ID = 800,
    TEXQUALITY_RADIO_H_ID,
    TEXQUALITY_RADIO_M_ID,
    TEXQUALITY_RADIO_L_ID,
    TEXQUALITY_RADIO_UL_ID,

    LT_RADIO_GRP_ID,
    LT_RADIO_H_ID,
    LT_RADIO_M_ID,
    LT_RADIO_L_ID,
    LT_RADIO_UL_ID,

    WATER_RADIO_GRP_ID,
    WATER_RADIO_H_ID,
    WATER_RADIO_M_ID,

    BUMP_RADIO_GRP_ID,
    BUMP_RADIO_ON_ID,
    BUMP_RADIO_OFF_ID,
  };

  PropertyContainerControlBase *mTabPage;
};


//==============================================================================
// PsCollisionTab
//==============================================================================
enum
{
  COLLIDER_CHECK_BOX_ID = 400,
};

class PsCollisionTab
{
public:
  PsCollisionTab(PropertyContainerControlBase *tab_page);

  bool onOkPressed();

private:
  PropertyContainerControlBase *mTabPage;
  Tab<String> mColNames;
};


enum
{
  DIALOG_TAB_PANEL,
  DIALOG_TAB_MAX,
  DIALOG_TAB_EXTERNAL_DATA,
  DIALOG_TAB_LIGHTING,
  DIALOG_TAB_MISC,
  DIALOG_TAB_COLLISION
};


#endif //__GAIJIN_DE_PROJECT_SETTINGS__
