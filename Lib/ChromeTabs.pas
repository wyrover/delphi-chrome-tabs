unit ChromeTabs;

// Version 0.9
//
// The contents of this file are subject to the Mozilla Public License
// Version 1.1 (the "License"); you may not use this file except in compliance
// with the License. You may obtain a copy of the License at http://www.mozilla.org/MPL/
//
// Alternatively, you may redistribute this library, use and/or modify it under the terms of the
// GNU Lesser General Public License as published by the Free Software Foundation;
// either version 2.1 of the License, or (at your option) any later version.
// You may obtain a copy of the LGPL at http://www.gnu.org/copyleft/.
//
// Software distributed under the License is distributed on an "AS IS" basis,
// WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License for the
// specific language governing rights and limitations under the License.
//
// The original code is ChromeTabs.pas, released December 2012.
//
// The initial developer of the original code is Easy-IP AS (Oslo, Norway, www.easy-ip.net),
// written by Paul Spencer Thornton (paul.thornton@easy-ip.net, www.easy-ip.net).
//
// Portions created by Easy-IP AS are Copyright
// (C) 2012 Easy-IP AS. All Rights Reserved.
//----------------------------------------------------------------------------------------------------------------------
//
// Inspiration for TChromeTabs came from TrkSmartTabs (http://www.rmklever.com) and
// TIceTabSet (http://sourceforge.net/projects/icetabset/).
//
// Thanks to Anders Melander for the transparent form tutorial (http://melander.dk/articles/alphasplash2/2/)
//
// Please send bug reports/feature requests/comments to paul.thornton@easy-ip.net
//
// For a list of recent changes please see file ChangeLog.txt
//
//----------------------------------------------------------------------------------------------------------------------
//
// Features:
// - Fully configurable Look and Feel including gradients, transparencies and custom tab shapes
// - Works on Vista glass
// - Tab movement animation
// - Tab transitional style effects (fade between colours and alpha levels)
// - Drag and Drop within container and between containers
// - Drag image displays tab and any TWinControl
// - Smart tab resizing when user clicks close button
// - Fluid tab resizing with minimum and maximum tab sizes
// - Add tab button can be positioned on the left, right or floating right
// - Full featured scrolling including auto scroll when dragging
// - Smart tab content display hides/shows items depending on the tab width
// - Owner draw any item
// - Right to Left text
// - Pinned tabs
// - Modified tabs with animated glow
// - Tab images and overlay images
// - Mouse over glow
// - Lots of events
// - Load/save look and feel and options to stream/file
// - Generate look and feel/options Delphi code
// - Full support for BiDi (Right to Left), including container, tabs and text

// - Demo includes look and feel editor and GUI access to all tab properties and features

interface

{ TODO -cImprovement : Selective invalidation of tabs }
{ TODO -cImprovement : Better handling of GDI text alpha on Vista Glass - How? }

{ TODO -cFeature : Tab busy spinners }

{ TODO -cBug : Tab Alpha increases slightly when drag begins }
{ TODO -cBug : Drag docking not accurate. Some problem with the control detection }
{ TODO -cBug : Why does setting a pen thinckess to a fraction (e.g. 1.5) not have any effect? }

{$include versions.inc}

uses
  Windows, SysUtils, Classes, Controls, ExtCtrls, Graphics, Forms, Messages,
  ImgList, Dialogs, Menus, StdCtrls, GraphUtil,

  GDIPObj, GDIPAPI,

  ChromeTabsTypes,
  ChromeTabsUtils,
  ChromeTabsControls,
  ChromeTabsThreadTimer,
  ChromeTabsClasses;

type
  TCustomChromeTabs = class;

  TOnDebugLog = procedure(Sender: TObject; const Text: String) of object;
  TOnButtonCloseTabClick = procedure(Sender: TObject; ATab: TChromeTab; var Close: Boolean) of object;
  TOnActiveTabChanging = procedure(Sender: TObject; AOldTab, ANewTab: TChromeTab; var Allow: Boolean) of object;
  TOnActiveTabChanged = procedure(Sender: TObject; ATab: TChromeTab) of object;
  TOnChange = procedure(Sender: TObject; ATab: TChromeTab; TabChangeType: TTabChangeType) of object;
  TOnNeedDragImageControl = procedure(Sender: TObject; ATab: TChromeTab; var DragControl: TWinControl) of object;
  TOnCreateDragForm = procedure(Sender: TObject; ATab: TChromeTab; var DragForm: TForm) of object;
  TOnStateChange = procedure(Sender: TObject; PreviousState: TChromeTabStates; CurrentState: TChromeTabStates) of object;
  TOnBeforeDrawItem = procedure(Sender: TObject; TargetCanvas: TGPGraphics; ItemRect: TRect; ItemType: TChromeTabItemType; TabIndex: Integer; var Handled: Boolean) of object;
  TOnAfterDrawItem = procedure(Sender: TObject; const TargetCanvas: TGPGraphics; ItemRect: TRect; ItemType: TChromeTabItemType; TabIndex: Integer) of object;
  TOnGetControlPolygons = procedure(Sender: TObject; ItemRect: TRect; ItemType: TChromeTabItemType; Orientation: TTabOrientation; var Polygons: IChromeTabPolygons) of object;
  TOnShowHint = procedure(Sender: TObject; HitTestResult: THitTestResult; var HintText: String; var HintTimeout: Integer) of object;
  TOnTabDblClick = procedure(Sender: TObject; ATab: TChromeTab) of object;
  TOnTabDragStart = procedure(Sender: TObject; ATab: TChromeTab; var Allow: Boolean) of object;
  TOnTabDragOver = procedure(Sender: TObject; X, Y: Integer; State: TDragState; DragTabObject: IDragTabObject; var Accept: Boolean) of object;
  TOnTabDragDrop = procedure(Sender: TObject; X, Y: Integer; DragTabObject: IDragTabObject; Cancelled: Boolean; var TabDropOptions: TTabDropOptions) of object;
  TOnTabDragDropped = procedure(Sender: TObject; DragTabObject: IDragTabObject; NewTab: TChromeTab) of object;
  TOnAnimateStyle = procedure(Sender: TObject; ChromeTabsControl: TBaseChromeTabsControl; NewDrawState: TDrawState; var AnimationTimeMS: Cardinal; var EaseType: TChromeTabsEaseType) of object;
  TOnAnimateMovement = procedure(Sender: TObject; ChromeTabsControl: TBaseChromeTabsControl; var AnimationTimeMS: Cardinal; var EaseType: TChromeTabsEaseType) of object;

  // Why do we need this?
  // See http://stackoverflow.com/questions/13915160/why-are-a-forms-system-buttons-highlighted-when-calling-windowfrompoint-in-mous/13943390#13943390
  TWindowFromPointFixThread = class(TThread)
  private
    FPoint: TPoint;
    FRange: Integer;
    FStep: Integer;
  public
    constructor Create(Pt: TPoint; Range, Step: Integer);

    procedure Execute; override;
  end;

  TCustomChromeTabs = class(TCustomControl, IChromeTabs, IChromeTabDockControl)
  private
    // IChromeTabInterface
    function GetLastPinnedIndex: Integer;
    function GetActiveTab: TChromeTab;
    function GetPreviousTabPolygons(Index: Integer): IChromeTabPolygons;
    function GetComponentState: TComponentState;
    function IsDragging: Boolean;

    // ITabDockControl
    function GetControl: TWinControl;
    procedure TabDragOver(Sender: TObject; X, Y: Integer; State: TDragState; DragTabObject: IDragTabObject; var Accept: Boolean);
    procedure TabDragDrop(Sender: TObject; X, Y: Integer; DragTabObject: IDragTabObject; Cancelled: Boolean; var TabDropOptions: TTabDropOptions);
    procedure DragCompleted;
    function InsertDroppedTab: TChromeTab;
    procedure FireScrollTimer;
  private
    // Events
    FOnActiveTabChanged: TOnActiveTabChanged;
    FOnActiveTabChanging: TOnActiveTabChanging;
    FOnChange: TOnChange;
    FOnButtonAddClick: TNotifyEvent;
    FOnButtonCloseTabClick: TOnButtonCloseTabClick;
    FOnMouseEnter: TNotifyEvent;
    FOnMouseLeave: TNotifyEvent;
    FOnDebugLog: TOnDebugLog;
    FOnNeedDragImageControl: TOnNeedDragImageControl;
    FOnCreateDragForm: TOnCreateDragForm;
    FOnBeginTabDrag: TOnTabDragStart;
    FOnStateChange: TOnStateChange;
    FOnBeforeDrawItem: TOnBeforeDrawItem;
    FOnAfterDrawItem: TOnAfterDrawItem;
    FOnGetControlPolygons: TOnGetControlPolygons;
    FOnShowHint: TOnShowHint;
    FOnTabDblClick: TOnTabDblClick;
    FOnTabDragStart: TOnTabDragStart;
    FOnTabDragOver: TOnTabDragOver;
    FOnTabDragDrop: TOnTabDragDrop;
    FOnTabDragDropped: TOnTabDragDropped;
    FOnScroll: TNotifyEvent;
    FOnScrollWidthChanged: TNotifyEvent;
    FOnAnimateStyle: TOnAnimateStyle;
    FOnAnimateMovement: TOnAnimateMovement;

    // Persistent Properties
    FOptions: TOptions;
    FLookAndFeel: TChromeTabsLookAndFeel;

    // Controls
    FAddButtonControl: TAddButtonControl;
    FScrollButtonLeftControl: TScrollButtonLeftControl;
    FScrollButtonRightControl: TScrollButtonRightControl;

    // Drag
    FDragTabObject: IDragTabObject;
    FActiveDragTabObject: IDragTabObject;

    FCanvasBmp: TBitmap;
    FBackgroundBmp: TBitmap;
    FTabPopupMenu: TPopupMenu;
    FImages: TCustomImageList;
    FImagesOverlay: TCustomImageList;
    FTabs: TChromeTabsList;
    FUpdateCount: Integer;
    FAnimateTimer: TThreadTimer;
    FScrollTimer: TTimer;
    FCancelTabSmartResizeTimer: TTimer;
    FPausedUpdateCount: Integer;
    FState: TChromeTabStates;
    FAdjustedTabWidth: Integer;
    FScrollWidth: Integer;
    FPreviousScrollWidth: Integer;
    FLastMouseX: Integer;
    FLastMouseY: Integer;
    FClosedTabRect: TRect;
    FClosedTabIndex: Integer;
    FInvalidatingControls: Boolean;
    FTabEndSpace: Integer;
    FScrollOffset: Integer;
    FTabContainerRect: TRect;
    FScrollDirection: TScrollDirection;
    FLastClientWidth: Integer;
    FLastHitTestResult: THitTestResult;
    FMovementEaseType: TChromeTabsEaseType;
    FMovementAnimationTime: Cardinal;
    FMaxAddButtonRight: Integer;
    FNextModifiedGlowAnimateTickCount: Cardinal;

    // Timer events
    procedure OnScrollTimerTimer(Sender: TObject);
    procedure OnCancelTabSmartResizeTimer(Sender: TObject);
    procedure OnAnimateTimer(Sender: TObject);

    // Propert Getters/Setters
    function GetOptions: TOptions;
    function GetImages: TCustomImageList;
    function GetImagesOverlay: TCustomImageList;
    function GetActiveTabIndex: Integer;
    function GetTabControl(Index: Integer): TChromeTabControl; virtual;
    function GetLookAndFeel: TChromeTabsLookAndFeel;

    procedure SetActiveTabIndex(const Value: Integer);
    procedure SetOptions(const Value: TOptions);
    procedure SetTabs(const Value: TChromeTabsList);
    procedure SetImages(const Value: TCustomImageList);
    procedure SetImagesOverlay(const Value: TCustomImageList);
    procedure SetActiveTab(const Value: TChromeTab);
    procedure SetLookAndFeel(Value: TChromeTabsLookAndFeel);

    function IsValidTabIndex(Index: Integer): Boolean;
    procedure Redraw;
    function GetLastPinnedTabIndex: Integer;
    function GetPinnedTabCount: Integer;
    procedure UpdateTabControlProperties;
    procedure InvalidateAllControls;
    procedure DrawBackGroundTo(Targets: Array of TGPGraphics);
    function ControlRect: TRect;
    procedure ClearTabClosingStates;
    procedure UpdateProperties;
    procedure ShowTabDragForm(X, Y: Integer; FormVisible: Boolean);
    function DraggingDockedTab: Boolean;
    function ActiveTabVisible: Boolean;
    function FindChromeTabsControlWithinRange(Pt: TPoint; Range: Integer; Step: Integer = 5): TCustomChromeTabs;
    function DraggingInOwnContainer: Boolean;
    function GetVisiblePinnedTabCount(IncludeMarkedForDelete: Boolean = FALSE): Integer;
    function GetVisibleNonPinnedTabCount(IncludeMarkedForDelete: Boolean = FALSE): Integer;
    function GetLastVisibleTabIndex(StartIndex: Integer): Integer;
    procedure SetScrollOffset(const Value: Integer);
    procedure SetScrollOffsetEx(const Value: Integer; IgnoreContraints: Boolean);
    function ScrollRect(ARect: TRect): TRect; overload;
    function ScrollRect(ALeft, ATop, ARight, ABottom: Integer): TRect; overload;
    procedure CorrectScrollOffset(AlwaysCorrect: Boolean = FALSE);
    function GetMaxScrollOffset: Integer;
    function ScrollButtonLeftVisible: Boolean;
    function ScrollButtonRightVisible: Boolean;
    procedure ScrollTabs(ScrollDirection: TScrollDirection; StartTimer: Boolean = TRUE);
    function CorrectedClientWidth: Integer;
    function GetVisibleTabCount(IncludeMarkedForDelete: Boolean = FALSE): Integer;
    function ScrollingActive: Boolean;
    procedure SetControlDrawState(ChromeTabsControl: TBaseChromeTabsControl; NewDrawState: TDrawState; ForceUpdate: Boolean = FALSE);
    function BidiRect(ARect: TRect): TRect;
    function GetBiDiMode: TBiDiMode;
    function GetBidiScrollOffset: Integer;
    function BidiXPos(X: Integer): Integer;
    function SameBidiTabMode(BidiMode1, BiDiMode2: TBidiMode): Boolean;
    procedure SetControlPosition(ChromeTabsControl: TBaseChromeTabsControl; ControlRect: TRect; Animate: Boolean);
    procedure SetControlLeft(ChromeTabsControl: TBaseChromeTabsControl; ALeft: Integer; Animate: Boolean);
    procedure SetMovementAnimation(MovementAnimationTypes: TChromeTabsMovementAnimationTypes);
    procedure DeleteTab(Index: Integer);
  protected
    // ** Important, often called procedures ** //
    procedure RepositionTabs; virtual;
    procedure DrawCanvas; virtual;
    procedure CalculateRects; virtual;
    procedure SetControlDrawStates(ForceUpdate: Boolean = FALSE); virtual;
  protected
    FMouseButton: TMouseButton;
    FMouseDownHitTest: THitTestResult;
    FMouseDownPoint: TPoint;
    FDragTabControl: TChromeTabControl;
    FDragCancelled: Boolean;

    // Messages
    procedure CMMouseEnter(var Msg: TMessage); message CM_MOUSEENTER;
    procedure CMMouseLeave(var Msg: TMessage); message CM_MOUSELEAVE;
    procedure CMHintShow(var Message: TCMHintShow); message CM_HINTSHOW;
    procedure WMLButtonDblClk(var Message: TWMLButtonDblClk); message WM_LBUTTONDBLCLK;
    procedure WMPaint(var Message: TWMPaint); message WM_PAINT;
    procedure WMERASEBKGND(var Message: TWMEraseBkgnd); message WM_ERASEBKGND;
    procedure WMWindowPosChanged(var Message: TWMWindowPosChanged); message WM_WINDOWPOSCHANGED;
    procedure WMContextMenu(var Message: TWMContextMenu); message WM_CONTEXTMENU;
    procedure WMMouseWheel(var Msg: TWMMouseWheel); message WM_MOUSEWHEEL;

    // Override
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; x, y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; x, y: Integer); override;
    procedure MouseMove(Shift: TShiftState; x, y: Integer); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure WndProc(var Message: TMessage); override;
    procedure SetBiDiMode(Value: TBiDiMode); override;
    procedure Loaded; override;

    // Virtual
    procedure DoOnActiveTabChanged(ATab: TChromeTab); virtual;
    procedure DoOnButtonCloseTabClick(ATab: TChromeTab; var AllowClose: Boolean); virtual;
    procedure DoOnButtonAddClick; virtual;
    procedure DoOnNeedDragImageControl(ATab: TChromeTab; var DragControl: TWinControl); virtual;
    procedure DoOnCreateDragForm(ATab: TChromeTab; var DragForm: TForm); virtual;
    procedure DoOnBeginTabDrag(ATab: TChromeTab; var Allow: Boolean); virtual;
    procedure DoOnStateChange(PreviousState: TChromeTabStates; CurrentState: TChromeTabStates); virtual;
    procedure DoOnMouseLeave; virtual;
    procedure DoOnShowHint(HitTestResult: THitTestResult; var HintText: String; var HintTimeout: Integer); virtual;
    procedure DoOnTabDblClick(ATab: TChromeTab); virtual;
    procedure DoOnTabDragStart(ATab: TChromeTab; var Allow: Boolean); virtual;
    procedure DoOnTabDragOver(X, Y: Integer; State: TDragState; DragTabObject: IDragTabObject; var Accept: Boolean); virtual;
    procedure DoOnTabDragDrop(X, Y: Integer; DragTabObject: IDragTabObject; Cancelled: Boolean; var TabDropOptions: TTabDropOptions); virtual;
    procedure DoOnTabDragDropped(DragTabObject: IDragTabObject; NewTab: TChromeTab); virtual;
    procedure DoOnScroll; virtual;
    procedure DoOnScrollWidthChanged; virtual;
    procedure DoPopup(Sender: TObject; APoint: TPoint); virtual;
    procedure DoPopupClick(Sender: TObject); virtual;
    procedure DoOnAnimateStyle(ChromeTabsControl: TBaseChromeTabsControl; NewDrawState: TDrawState; var AnimationTimeMS: Cardinal; var EaseType: TChromeTabsEaseType); virtual;
    procedure DoOnAnimateMovement(ChromeTabsControl: TBaseChromeTabsControl; var AnimationTimeMS: Cardinal; var EaseType: TChromeTabsEaseType); virtual;

    // Virtual (IChromeTabInterface)
    procedure DoOnBeforeDrawItem(TargetCanvas: TGPGraphics; ItemRect: TRect; ItemType: TChromeTabItemType; TabIndex: Integer; var Handled: Boolean); virtual;
    procedure DoOnAfterDrawItem(const TargetCanvas: TGPGraphics; ItemRect: TRect; ItemType: TChromeTabItemType; TabIndex: Integer); virtual;
    procedure DoOnGetControlPolygons(ItemRect: TRect; ItemType: TChromeTabItemType; Orientation: TTabOrientation; var Polygons: IChromeTabPolygons); virtual;
    procedure DoOnDebugLog(const Text: String; Args: Array of const); virtual;
    procedure DoOnActiveTabChanging(AOldTab, ANewTab: TChromeTab; var Allow: Boolean);
    procedure DoOnChange(ATab: TChromeTab; TabChangeType: TTabChangeType);

    // General
    function DragTabInTabRect(MouseX, MouseY: Integer): Boolean; virtual;
    function CreateDragForm(ATab: TChromeTab): TForm; virtual;
    function AddState(State: TChromeTabState): Boolean; virtual;
    function RemoveState(State: TChromeTabState): Boolean; virtual;
  protected
    property OnActiveTabChanging: TOnActiveTabChanging read FOnActiveTabChanging write FOnActiveTabChanging;
    property OnActiveTabChanged: TOnActiveTabChanged read FOnActiveTabChanged write FOnActiveTabChanged;
    property OnChange: TOnChange read FOnChange write FOnChange;
    property OnButtonCloseTabClick: TOnButtonCloseTabClick read FOnButtonCloseTabClick write FOnButtonCloseTabClick;
    property OnButtonAddClick: TNotifyEvent read FOnButtonAddClick write FOnButtonAddClick;
    property OnDebugLog: TOnDebugLog read FOnDebugLog write FOnDebugLog;
    property OnNeedDragImageControl: TOnNeedDragImageControl read FOnNeedDragImageControl write FOnNeedDragImageControl;
    property OnCreateDragForm: TOnCreateDragForm read FOnCreateDragForm write FOnCreateDragForm;
    property OnStateChange: TOnStateChange read FOnStateChange write FOnStateChange;
    property OnBeforeDrawItem: TOnBeforeDrawItem read FOnBeforeDrawItem write FOnBeforeDrawItem;
    property OnAfterDrawItem: TOnAfterDrawItem read FOnAfterDrawItem write FOnAfterDrawItem;
    property OnGetControlPolygons: TOnGetControlPolygons read FOnGetControlPolygons write FOnGetControlPolygons;
    property OnShowHint: TOnShowHint read FOnShowHint write FOnShowHint;
    property OnTabDblClick: TOnTabDblClick read FOnTabDblClick write FOnTabDblClick;
    property OnTabDragStart: TOnTabDragStart read FOnTabDragStart write FOnTabDragStart;
    property OnTabDragOver: TOnTabDragOver read FOnTabDragOver write FOnTabDragOver;
    property OnTabDragDrop: TOnTabDragDrop read FOnTabDragDrop write FOnTabDragDrop;
    property OnTabDragDropped: TOnTabDragDropped read FOnTabDragDropped write FOnTabDragDropped;
    property OnScroll: TNotifyEvent read FOnScroll write FOnScroll;
    property OnScrollWidthChanged: TNotifyEvent read FOnScrollWidthChanged write FOnScrollWidthChanged;
    property OnAnimateStyle: TOnAnimateStyle read FOnAnimateStyle write FOnAnimateStyle;
    property OnAnimateMovement: TOnAnimateMovement read FOnAnimateMovement write FOnAnimateMovement;

    property LookAndFeel: TChromeTabsLookAndFeel read GetLookAndFeel write SetLookAndFeel;
    property ActiveTabIndex: Integer read GetActiveTabIndex write SetActiveTabIndex;
    property Images: TCustomImageList read GetImages write SetImages;
    property ImagesOverlay: TCustomImageList read GetImagesOverlay write SetImagesOverlay;
    property Options: TOptions read GetOptions write SetOptions;
    property Tabs: TChromeTabsList read FTabs write SetTabs;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure BeginUpdate;
    procedure EndUpdate;

    procedure BeginDrag(MouseX, MouseY: Integer);
    procedure EndDrag(MouseX, MouseY: Integer; Cancelled: Boolean);

    function GetTabDescription(Index: Integer): String;
    procedure PaintWindow(DC: HDC); override;
    procedure Resize; override;
    function HitTest(pt: TPoint; IgnoreDisabledControls: Boolean = FALSE): THitTestResult; virtual;
    function HasState(State: TChromeTabState): Boolean; virtual;
    procedure ScrollIntoView(Tab: TChromeTab); virtual;
    function GetTabUnderMouse: TChromeTab;
    function GetTabDisplayState: TTabDisplayState;

    procedure SaveLookAndFeel(Stream: TStream); overload; virtual;
    procedure SaveLookAndFeel(const Filename: String); overload; virtual;
    procedure LoadLookAndFeel(Stream: TStream); overload; virtual;
    procedure LoadLookAndFeel(const Filename: String); overload; virtual;
    procedure SaveOptions(Stream: TStream); overload; virtual;
    procedure SaveOptions(const Filename: String); overload; virtual;
    procedure LoadOptions(Stream: TStream); overload; virtual;
    procedure LoadOptions(const Filename: String); overload; virtual;
    function LookAndFeelToCode: String;
    function OptionsToCode: String;

    property ActiveDragTabObject: IDragTabObject read FActiveDragTabObject;
    property TabControls[Index: Integer]: TChromeTabControl read GetTabControl;
    property ActiveTab: TChromeTab read GetActiveTab write SetActiveTab;
    property State: TChromeTabStates read FState;
    property PausedUpdateCount: Integer read FPausedUpdateCount;
    property ScrollOffset: Integer read FScrollOffset write SetScrollOffset;
    property BidiScrollOffset: Integer read GetBidiScrollOffset;
    property ScrollWidth: Integer read FScrollWidth;
    property TabContainerRect: TRect read FTabContainerRect;
    property MaxScrollOffset: Integer read GetMaxScrollOffset;
    property LastMouseX: Integer read FLastMouseX;
    property LastMouseY: Integer read FLastMouseY;
  end;

  TChromeTabs = class(TCustomChromeTabs)
  published
    property OnActiveTabChanging;
    property OnChange;
    property OnActiveTabChanged;
    property OnDebugLog;
    property OnButtonAddClick;
    property OnButtonCloseTabClick;
    property OnNeedDragImageControl;
    property OnCreateDragForm;
    property OnStateChange;
    property OnBeforeDrawItem;
    property OnAfterDrawItem;
    property OnGetControlPolygons;
    property OnShowHint;
    property OnTabDblClick;
    property OnTabDragStart;
    property OnTabDragOver;
    property OnTabDragDrop;
    property OnTabDragDropped;
    property OnScroll;
    property OnScrollWidthChanged;
    property OnAnimateStyle;
    property OnAnimateMovement;

    property ActiveTabIndex;
    property Images;
    property ImagesOverlay;
    property Options;
    property Tabs;
    property LookAndFeel;
    property BiDiMode;

    property Align;
    property Anchors;
    property Enabled;
    property Font;
    property PopupMenu;
    property ShowHint;
    property TabStop;
    property Visible;
    property OnClick;
    property OnDblClick;
    property OnEnter;
    property OnExit;
    property OnKeyDown;
    property OnKeyUp;
    property OnMouseDown;
    property OnMouseUp;
    property OnMouseMove;
    property OnResize;
    property TabOrder;
    {$IFDEF DELPHI2006_UP}   { TODO : Is this the version when these events were introduced? }
      property OnMouseEnter;
      property OnMouseLeave;
    {$ENDIF}
  end;

implementation

const
  TabDragScaleFactor = 0.7;
  DefaultCodeComponentName = 'ChromeTabs1';

resourcestring
  StrNoCaption = '<No Caption>';
  StrPinThisTab = 'Pin this tab';
  StrUnpinThisTab = 'Unpin this tab';
  StrNewTab = 'New tab';
  StrDeleteTab = 'Delete Tab';

{ TChromeTabs }

function TCustomChromeTabs.FindChromeTabsControlWithinRange(Pt: TPoint; Range: Integer; Step: Integer): TCustomChromeTabs;
var
  WindowFromPointFixThread: TWindowFromPointFixThread;
begin
  WindowFromPointFixThread := TWindowFromPointFixThread.Create(Pt, Range, Step);
  try
    Result := TCustomChromeTabs(WindowFromPointFixThread.WaitFor);
  finally
    FreeAndNil(WindowFromPointFixThread);
  end;
end;

function TCustomChromeTabs.GetPinnedTabCount: Integer;
begin
  Result := GetLastPinnedTabIndex + 1;
end;

function TCustomChromeTabs.GetPreviousTabPolygons(
  Index: Integer): IChromeTabPolygons;
var
  PreviousIndex: Integer;
begin
  PreviousIndex := GetLastVisibleTabIndex(Index - 1);

  if PreviousIndex = -1 then
    Result := nil
  else
    Result := TabControls[PreviousIndex].GetPolygons;
end;

function TCustomChromeTabs.GetVisiblePinnedTabCount(IncludeMarkedForDelete: Boolean): Integer;
var
  i: Integer;
begin
  Result := 0;

  for i := 0 to pred(GetPinnedTabCount) do
    if (Tabs[i].Visible) and ((IncludeMarkedForDelete) or (not Tabs[i].MarkedForDeletion)) then
      Inc(Result);
end;

function TCustomChromeTabs.GetVisibleTabCount(IncludeMarkedForDelete: Boolean): Integer;
begin
  Result := GetVisiblePinnedTabCount(IncludeMarkedForDelete) + GetVisibleNonPinnedTabCount(IncludeMarkedForDelete);
end;

function TCustomChromeTabs.GetVisibleNonPinnedTabCount(IncludeMarkedForDelete: Boolean): Integer;
var
  i: Integer;
begin
  Result := 0;

  for i := GetLastPinnedIndex + 1 to pred(Tabs.Count) do
    if (Tabs[i].Visible) and ((IncludeMarkedForDelete) or (not Tabs[i].MarkedForDeletion)) then
      Inc(Result);
end;

procedure TCustomChromeTabs.BeginDrag(MouseX, MouseY: Integer);
var
  HitTestResult: THitTestResult;
  Accept, Allow: Boolean;
begin
  ClearTabClosingStates;

  HitTestResult := HitTest(Point(MouseX, MouseY));

  if HitTestResult.TabIndex = -1 then
    EndDrag(MouseX, MouseY, TRUE)
  else
  begin
    Allow := FOptions.DragDrop.DragType in [dtWithinContainer, dtBetweenContainers];

    DoOnTabDragStart(Tabs[HitTestResult.TabIndex], Allow);

    if not Allow then
      EndDrag(MouseX, MouseY, TRUE)
    else
    begin
      SetMovementAnimation(FOptions.Animation.MovementAnimations.TabMove);

      FDragTabObject := TDragTabObject.Create;

      AddState(stsDragging);
      AddState(stsDragStarted);

      FDragTabObject.DragTab := Tabs[HitTestResult.TabIndex];
      FDragTabObject.DragCursorOffset := Point(MouseX - BidiXPos(TabControls[HitTestResult.TabIndex].ControlRect.Left) + BidiScrollOffset,
                                               MouseY - TabControls[HitTestResult.TabIndex].ControlRect.Top);
      FDragTabObject.HideAddButton := FALSE;
      FDragTabObject.DragPoint := FMouseDownPoint;
      FDragTabObject.OriginalControlRect := TabControls[HitTestResult.TabIndex].ControlRect;
      FDragTabObject.DropTabIndex := HitTestResult.TabIndex;
      FDragTabObject.OriginalCursor := Screen.Cursor;
      FDragTabObject.SourceControl := Self;
      FDragTabObject.DockControl := Self;

      Screen.Cursor := FOptions.DragDrop.DragCursor;

      FDragTabObject.DockControl.TabDragOver(Self, MouseX, MouseY, dsDragEnter, FDragTabObject, Accept);
    end;
  end;
end;

procedure TCustomChromeTabs.BeginUpdate;
begin
  if FUpdateCount = 0 then
    FPausedUpdateCount := 0;

  Inc(FUpdateCount);
end;

procedure TCustomChromeTabs.CMMouseEnter(var Msg: TMessage);
begin
  FCancelTabSmartResizeTimer.Enabled := FALSE;

  if Assigned(FOnMouseEnter) then
    FOnMouseEnter(Self);
end;

procedure TCustomChromeTabs.CMMouseLeave(var Msg: TMessage);
begin
  FLastMouseX := -1;
  FLastMouseY := -1;

  SetControlDrawStates;

  // Remove the closing state so the frozen tabs get resized and
  // redraw if required
  FCancelTabSmartResizeTimer.Enabled := TRUE;
  
  Redraw;

  DoOnMouseLeave;
end;

function TCustomChromeTabs.GetTabDisplayState: TTabDisplayState;
begin
  if (GetVisibleTabCount = 0) or (FAdjustedTabWidth = FOptions.Display.Tabs.MaxWidth) then
    Result := tdNormal else
  if ScrollingActive then
    Result := tdScrolling
  else
    Result := tdCompressed;
end;

procedure TCustomChromeTabs.ClearTabClosingStates;
begin
  RemoveState(stsDeletingUnPinnedTabs);
  RemoveState(stsTabDeleted);
  RemoveState(stsEndTabDeleted);

  Redraw;
end;

procedure TCustomChromeTabs.DoOnMouseLeave;
begin
  //SetControlDrawStates(TRUE);

  if Assigned(FOnMouseLeave) then
    FOnMouseLeave(Self);
end;

function TCustomChromeTabs.InsertDroppedTab: TChromeTab;
begin
  Result := nil;

  if FActiveDragTabObject <> nil then
  begin
    BeginUpdate;
    try
      // Move the tab between the controls
      AddState(stsAddingDroppedTab);
      try
        Result := Tabs.Add;
      finally
        RemoveState(stsAddingDroppedTab);
      end;

      // Set the tab properties
      Result.Data := FActiveDragTabObject.DragTab.Data;
      Result.Caption := FActiveDragTabObject.DragTab.Caption;
      Result.ImageIndex := FActiveDragTabObject.DragTab.ImageIndex;
      Result.ImageIndexOverlay := FActiveDragTabObject.DragTab.ImageIndexOverlay;
      Result.Pinned := FActiveDragTabObject.DragTab.Pinned;

      Tabs.Move(Result.Index, FActiveDragTabObject.DropTabIndex);

      // Move the dropped tab to a new position
      SetControlPosition(TabControls[FActiveDragTabObject.DropTabIndex],
                         FDragTabControl.ControlRect,
                         FALSE);

      Result.Active := TRUE;
    finally
      EndUpdate;
    end;
  end;
end;

function TCustomChromeTabs.AddState(State: TChromeTabState): Boolean;
var
  PreviousState: TChromeTabStates;
begin
  Result := not HasState(State);

  if Result then
  begin
    FState := FState + [State];

    DoOnStateChange(PreviousState, FState);
  end;
end;

function TCustomChromeTabs.RemoveState(State: TChromeTabState): Boolean;
var
  PreviousState: TChromeTabStates;
begin
  Result := HasState(State);

  if Result then
  begin
    FState := FState - [State];

    DoOnStateChange(PreviousState, FState);
  end;
end;

function TCustomChromeTabs.HasState(State: TChromeTabState): Boolean;
begin
  Result := State in FState;
end;

procedure TCustomChromeTabs.DoOnAnimateMovement(
  ChromeTabsControl: TBaseChromeTabsControl; var AnimationTimeMS: Cardinal;
  var EaseType: TChromeTabsEaseType);
begin
  if Assigned(FOnAnimateMovement) then
    FOnAnimateMovement(Self, ChromeTabsControl, AnimationTimeMS, EaseType);
end;

procedure TCustomChromeTabs.DoOnAnimateStyle(ChromeTabsControl: TBaseChromeTabsControl; NewDrawState: TDrawState; var AnimationTimeMS: Cardinal; var EaseType: TChromeTabsEaseType);
begin
  if Assigned(FOnAnimateStyle) then
    FOnAnimateStyle(Self, ChromeTabsControl, NewDrawState, AnimationTimeMS, EaseType);
end;

procedure TCustomChromeTabs.SetControlDrawState(ChromeTabsControl: TBaseChromeTabsControl; NewDrawState: TDrawState; ForceUpdate: Boolean);
var
  AnimationTimeMS: Cardinal;
  EaseType: TChromeTabsEaseType;
begin
  if (ChromeTabsControl.DrawState <> NewDrawState) or (ForceUpdate) then
  begin
    if (not (csDesigning in ComponentState)) and
       (((ChromeTabsControl.DrawState = dsHot) and ((NewDrawState <> dsActive)) or (not (ChromeTabsControl is TChromeTabControl))) or
        ((NewDrawState = dsHot) and (ChromeTabsControl.DrawState <> dsActive)) or (not (ChromeTabsControl is TChromeTabControl))) then
      EaseType := FOptions.Animation.DefaultMovementEaseType
    else
      EaseType := ttNone;

    AnimationTimeMS := FOptions.Animation.DefaultStyleAnimationTimeMS;

    if (ChromeTabsControl.DrawState <> NewDrawState) and (not (csDesigning in ComponentState)) then
      DoOnAnimateStyle(ChromeTabsControl, NewDrawState, AnimationTimeMS, EaseType);

    ChromeTabsControl.SetDrawState(NewDrawState, AnimationTimeMS, EaseType, ForceUpdate);
  end;
end;

procedure TCustomChromeTabs.SetControlDrawStates(ForceUpdate: Boolean);
var
  i: Integer;
  HitTestResult: THitTestResult;
begin
  // Don't update the control states if we're dragging
  if FActiveDragTabObject = nil then
  begin
    BeginUpdate;
    try
      HitTestResult := HitTest(Point(FLastMouseX, FLastMouseY), FALSE);

      if (ForceUpdate) or
         ((not HasState(stsPendingUpdates)) and
          ((FLastHitTestResult.HitTestArea <> HitTestResult.HitTestArea) or
           (FLastHitTestResult.TabIndex <> HitTestResult.TabIndex))) then
      begin
        FLastHitTestResult := HitTestResult;

        if (BiDiMode in BidiLeftToRightTabModes) and (ScrollOffset = 0) or
           (BiDiMode in BidiRightToLeftTabModes) and (ScrollOffset = GetMaxScrollOffset) then
          SetControlDrawState(FScrollButtonLeftControl, dsDisabled, ForceUpdate)
        else
          SetControlDrawState(FScrollButtonLeftControl, dsActive, ForceUpdate);

        if (BiDiMode in BidiLeftToRightTabModes) and (ScrollOffset = GetMaxScrollOffset) or
           (BiDiMode in BidiRightToLeftTabModes) and (ScrollOffset = 0) then
          SetControlDrawState(FScrollButtonRightControl, dsDisabled, ForceUpdate)
        else
          SetControlDrawState(FScrollButtonRightControl, dsActive, ForceUpdate);

        // Clear new button hot state
        SetControlDrawState(FAddButtonControl, dsNotActive, ForceUpdate);

        if HitTestResult.HitTestArea = htAddButton then
        begin
          if HasState(stsMouseDown) then
            SetControlDrawState(FAddButtonControl, dsDown, ForceUpdate)
          else
            SetControlDrawState(FAddButtonControl, dsHot, ForceUpdate);
        end else

        if HitTestResult.HitTestArea = htScrollButtonLeft then
        begin
          if ScrollOffset > 0 then
          begin
            if HasState(stsMouseDown) then
              SetControlDrawState(FScrollButtonLeftControl, dsDown, ForceUpdate)
            else
              SetControlDrawState(FScrollButtonLeftControl, dsHot, ForceUpdate);
          end;
        end else

        if HitTestResult.HitTestArea = htScrollButtonRight then
        begin
          if ScrollOffset < GetMaxScrollOffset then
          begin
            if HasState(stsMouseDown) then
              SetControlDrawState(FScrollButtonRightControl, dsDown, ForceUpdate)
            else
              SetControlDrawState(FScrollButtonRightControl, dsHot, ForceUpdate);
          end;
        end
        else
        begin
          // Clear hot tabs
          for i := 0 to pred(Tabs.Count) do
          begin
            if (HitTestResult.TabIndex = i) and (not HasState(stsDragging)) then
            begin
              if not Tabs[i].Active then
                SetControlDrawState(TabControls[i], dsHot, ForceUpdate);

              if HitTestResult.HitTestArea = htCloseButton then
              begin
                if HasState(stsMouseDown) then
                  TabControls[i].CloseButtonState := dsDown
                else
                  TabControls[i].CloseButtonState := dsHot
              end
              else
              begin
                if FTabs[i].Active then
                  TabControls[i].CloseButtonState := dsActive
                else
                  TabControls[i].CloseButtonState := dsNotActive;
              end;
            end
            else
            begin
              if not Tabs[i].Active then
                SetControlDrawState(TabControls[i], dsNotActive, ForceUpdate);

              TabControls[i].CloseButtonState := dsNotActive
            end;
          end;
        end;
      end;
    finally
      EndUpdate;
    end;
  end;
end;

procedure TCustomChromeTabs.SetImages(const Value: TCustomImageList);
begin
  FImages := Value;

  Redraw;
end;

procedure TCustomChromeTabs.SetOptions(const Value: TOptions);
begin
  FOptions.Assign(Value);
end;

procedure TCustomChromeTabs.SetScrollOffset(const Value: Integer);
begin
  SetScrollOffsetEx(Value, FALSE);
end;

function TCustomChromeTabs.GetMaxScrollOffset: Integer;
begin
  Result := FScrollWidth - RectWidth(TabContainerRect);

  if Tabs.Count > 1 then
    Result := Result + FOptions.Display.Tabs.TabOverlap;

  if Result < 0 then
    Result := 0;
end;

procedure TCustomChromeTabs.SetScrollOffsetEx(const Value: Integer; IgnoreContraints: Boolean);
begin
  if (FOptions.Scrolling.Enabled) and (Value <> FScrollOffset) then
  begin
    FScrollOffset := Value;

    if (not IgnoreContraints) and
       (Tabs.Count > 0) and
       (FScrollOffset > GetMaxScrollOffset) then
      FScrollOffset := GetMaxScrollOffset;

    if FScrollOffset < 0 then
      FScrollOffset := 0;

    AddState(stsControlPositionsInvalidated);

    SetControlDrawStates(TRUE);

    Redraw;

    DoOnScroll;
  end;
end;

procedure TCustomChromeTabs.SetImagesOverlay(const Value: TCustomImageList);
begin
  FImagesOverlay := Value;

  Redraw;
end;

procedure TCustomChromeTabs.DeleteTab(Index: Integer);
begin
  FTabs.DeleteTab(Index, csDesigning in ComponentState);
end;

procedure TCustomChromeTabs.DoPopupClick(Sender: TObject);
var
  OperationID: Integer;
begin
  OperationID := (Sender as TMenuItem).Tag;

  if FMouseDownHitTest.TabIndex <> -1 then
  begin
    if OperationID = 0 then
      Tabs[FMouseDownHitTest.TabIndex].Pinned := TRUE else

    if OperationID = 1 then
      Tabs[FMouseDownHitTest.TabIndex].Pinned := FALSE;

    if OperationID = 2 then
      DeleteTab(FMouseDownHitTest.TabIndex);
  end;

  if OperationID = 3 then
    DoOnButtonAddClick
  else
  if OperationID >= 10 then
    Tabs.ActiveTab := Tabs[OperationID - 10];

  Redraw;
end;

procedure TCustomChromeTabs.EndDrag(MouseX, MouseY: Integer; Cancelled: Boolean);
var
  DummyAccept: Boolean;
  NewTab: TChromeTab;
  DockControl, SourceControl: IChromeTabDockControl;
  TabDropOptions: TTabDropOptions;
begin
  try
    if FDragTabObject <> nil then
    begin
      NewTab := nil;

      Screen.Cursor := FDragTabObject.OriginalCursor;

      if FDragTabObject.DockControl <> nil then
      begin
        try
          if FDragTabObject.DockControl = FDragTabObject.SourceControl then
            TabDropOptions := [tdMoveTab]
          else
            TabDropOptions := [tdDeleteDraggedTab, tdCreateDroppedTab];

          FDragTabObject.DockControl.TabDragDrop(Self, MouseX, MouseY, FDragTabObject, Cancelled, TabDropOptions);

          if (Cancelled) or
             (FDragTabObject.DockControl.GetControl = FDragTabObject.SourceControl.GetControl) then
          begin
            // We've just moved the tab within this control
            if (Cancelled) or
               (FDragTabObject.DropTabIndex = -1) or
               (FDragTabObject.DragTab.Index = FDragTabObject.DropTabIndex) then
            begin
              AddState(stsCancellingDrag);

              Redraw;
            end
            else
            begin
              AddState(stsCompletingDrag);

              if tdMoveTab in TabDropOptions then
              begin
                // Move tab to new posisiton
                Tabs.Move(FDragTabObject.DragTab.Index, FDragTabObject.DropTabIndex);
              end;
            end;
          end else

          if FDragTabObject.DockControl <> nil then
          begin
            // We've dropped the tab on another tab control
            // Insert the dropped tab in the dock
            if tdCreateDroppedTab in TabDropOptions then
              NewTab := FDragTabObject.DockControl.InsertDroppedTab;
          end
        finally
          FDragTabObject.DockControl.TabDragOver(Self, MouseX, MouseY, dsDragLeave, FDragTabObject, DummyAccept);

          if NewTab <> nil then
            DoOnTabDragDropped(FDragTabObject, NewTab);
        end;
      end
      else
      begin
        // We've dropped the tab outside a tab control
        TabDropOptions := [tdDeleteDraggedTab];

        TabDragDrop(Self, MouseX, MouseY, FDragTabObject, Cancelled, TabDropOptions);
      end;
    end;
  finally
    DockControl := FDragTabObject.DockControl;
    SourceControl := FDragTabObject.SourceControl;

    FDragTabObject := nil;
    FActiveDragTabObject := nil;
    FDragTabControl := nil;
    FDragCancelled := FALSE;

    if (tdDeleteDraggedTab in TabDropOptions) and (ActiveTabIndex <> -1) then
      FTabs.DeleteTab(ActiveTabIndex, TRUE);

    RemoveState(stsDragging);

    if DockControl <> nil then
      DockControl.DragCompleted;

    SourceControl.DragCompleted;
  end;
end;

procedure TCustomChromeTabs.EndUpdate;
begin
  if FUpdateCount > 0 then
  begin
    Dec(FUpdateCount);

    if (FUpdateCount = 0) and
       (FPausedUpdateCount > 0) then
    begin
      FPausedUpdateCount := 0;

      Redraw;
    end;
  end;
end;

function TCustomChromeTabs.DragTabInTabRect(MouseX, MouseY: Integer): Boolean;
var
  DragRect: TRect;
begin
  Result := TRUE;

  if (HasState(stsDragging)) and
     (FOptions.DragDrop.DragType <> dtNone) then
  begin
    DragRect := BidiRect(TabContainerRect);
    RectInflate(DragRect, FOptions.DragDrop.DragOutsideDistancePixels);

    Result := PtInRect(DragRect, Point(MouseX, MouseY));
  end;
end;

function TCustomChromeTabs.GetLastVisibleTabIndex(StartIndex: Integer): Integer;
var
  i: Integer;
begin
  Result := -1;

  for i := StartIndex downto 0 do
    if FTabs[i].Visible then
    begin
      Result := i;

      Break;
    end;
end;

procedure TCustomChromeTabs.DoOnChange(ATab: TChromeTab; TabChangeType: TTabChangeType);
var
  i: Integer;
  NewTabControl: TChromeTabControl;
  NewTabLeft, LastVisibleTabIndex: Integer;
begin
  if not (csDestroying in ComponentState) then
  begin
    if (TabChangeType = tcAdded) and
       (ATab.TabControl = nil) then
    begin
      // If we are adding a new tab, we also need to create the corresponding
      // TabControl. The TabControl will be freed by the Tab
      ATab.TabControl := TChromeTabControl.Create(Self, ATab);

      NewTabControl := TabControls[ATab.Index];

      if (not HasState(stsLoading)) and (FOptions.Animation.GetMovementAnimationEaseType(FOptions.Animation.MovementAnimations.TabAdd) <> ttNone) then
      begin
        LastVisibleTabIndex := GetLastVisibleTabIndex(Tabs.Count - 2); // Skip the new tab

        if LastVisibleTabIndex <> -1 then
          NewTabLeft := TabControls[LastVisibleTabIndex].ControlRect.Right - FOptions.Display.Tabs.TabOverlap
        else
          NewTabLeft := FOptions.Display.Tabs.OffsetLeft + FOptions.Display.TabContainer.PaddingLeft;

        SetMovementAnimation(FOptions.Animation.MovementAnimations.TabAdd);

        SetControlPosition(NewTabControl,
                           Rect(NewTabLeft,
                                FOptions.Display.Tabs.OffsetTop,
                                NewTabLeft + FOptions.Animation.MinimumTabAnimationWidth,
                                ClientHeight - FOptions.Display.Tabs.OffsetBottom),
                                FALSE);
      end;

      // Fire the added event here before we activate the tab
      if Assigned(FOnChange) then
        FOnChange(Self, ATab, TabChangeType);

      // If no tabs are active, activate this one
      if (FOptions.Behaviour.ActivateNewTab) and
         ((ActiveTabIndex = -1) or
          ((not HasState(stsLoading) and
           (not HasState(stsAddingDroppedTab))))) then
      begin
        ATab.Active := TRUE;

        AddState(stsAnimatingNewTab);
      end
      else
      begin
        SetControlDrawState(TabControls[ATab.Index], dsNotActive);
      end;
    end;

    case TabChangeType of
      tcActivated:
        begin
          SetControlDrawState(TabControls[ATab.Index], dsActive);

          if FOptions.Scrolling.Enabled then
            ScrollIntoView(ATab);

          DoOnActiveTabChanged(ATab);
        end;

      tcDeactivated:
        begin
          SetControlDrawState(TabControls[ATab.Index], dsNotActive);

          // Is there an active tab?
          if ActiveTab = nil then
          begin
            // Make sure a tab is active
            for i := ATab.Index + 1 to pred(Tabs.Count) do
              if Tabs[i].Visible then
              begin
                Tabs[i].Active := TRUE;

                Break;
              end;
          end;

          // Still no active tab?
          if ActiveTab = nil then
          begin
            // Make sure a tab is active
            for i := pred(ATab.Index) downto 0 do
              if Tabs[i].Visible then
              begin
                Tabs[i].Active := TRUE;

                Break;
              end;
          end;
        end;

      tcPinned: AddState(stsControlPositionsInvalidated);

      tcPropertyUpdated:
        begin
          UpdateProperties;

          InvalidateAllControls;
        end;

      tcAdded: ClearTabClosingStates;

      tcVisibility: AddState(stsControlPositionsInvalidated);

      tcDeleted:
        begin
          SetMovementAnimation(FOptions.Animation.MovementAnimations.TabDelete);

          // We're deleting the tab but we need to animate it first
          if (FOptions.Animation.GetMovementAnimationEaseType(FOptions.Animation.MovementAnimations.TabDelete) <> ttNone) and
             (ATab <> nil) then
          begin
            // If the tabs are compressed and this is the last tab, don't animate
            if (GetTabDisplayState = tdCompressed) and (ATab.Index = Tabs.Count - 1) then
            begin
              Tabs.DeleteTab(ATab.Index, TRUE);
            end
            else
            begin
              AddState(stsAnimatingCloseTab);

              TabControls[ATab.Index].SetWidth(FOptions.Animation.MinimumTabAnimationWidth,
                                               FOptions.Animation.GetMovementAnimationTime(FOptions.Animation.MovementAnimations.TabDelete),
                                               FOptions.Animation.GetMovementAnimationEaseType(FOptions.Animation.MovementAnimations.TabDelete));
            end;
          end;
        end;

      tcDeleting:
        begin
          if FOptions.Behaviour.TabSmartDeleteResizing then
          begin
            if ATab.Index = Tabs.Count - 1 then
              AddState(stsEndTabDeleted)
            else
              AddState(stsTabDeleted);
          end;
        end;

      tcControlState:
        begin
          if ATab <> nil then
            TabControls[ATab.Index].Invalidate;
        end;
    end;

    if (FTabs <> nil) and (ActiveTabIndex = -1) and (GetVisibleTabCount > 0) then
      ActiveTabIndex := GetLastVisibleTabIndex(FTabs.Count - 1);

    Redraw;

    if (Assigned(FOnChange)) and (TabChangeType <> tcAdded) then
      FOnChange(Self, ATab, TabChangeType);
  end;
end;

procedure TCustomChromeTabs.UpdateProperties;
begin
  if not HasState(stsLoading) then
  begin
    FAnimateTimer.Interval := FOptions.Animation.AnimationTimerInterval;
    FCancelTabSmartResizeTimer.Interval := FOptions.Behaviour.TabSmartDeleteResizeCancelDelay;
    FScrollTimer.Interval := FOptions.Scrolling.ScrollRepeatDelay;
  end;
end;

procedure TCustomChromeTabs.WMMouseWheel(var Msg: TWMMouseWheel);
begin
  if (FOptions.Scrolling.Enabled) and
     (FOptions.Scrolling.MouseWheelScroll) and
     (Visible) and
     (Msg.WheelDelta <> 0) then
  begin
    ScrollOffset := ScrollOffset + Msg.WheelDelta;

    Msg.Result := 1;
  end;
end;

procedure TCustomChromeTabs.DoOnActiveTabChanged(ATab: TChromeTab);
begin
  if Assigned(FOnActiveTabChanged) then
    FOnActiveTabChanged(Self, ATab);
end;

procedure TCustomChromeTabs.DoOnActiveTabChanging(AOldTab, ANewTab: TChromeTab;
  var Allow: Boolean);
begin
  if Assigned(FOnActiveTabChanging) then
    FOnActiveTabChanging(Self, AOldTab, ANewTab, Allow);
end;

procedure TCustomChromeTabs.DoPopup(Sender: TObject; APoint: TPoint);
var
  i: Integer;
  AMenuItem: TMenuItem;

  procedure AddMenuItem(Name: string; Idx: Integer);
  begin
    AMenuItem := TMenuItem.Create(FTabPopupMenu);
    AMenuItem.Caption := Name;
    AMenuItem.OnClick := DoPopupClick;
    AMenuItem.Tag := Idx;
    AMenuItem.RadioItem := (Idx <> -1) and (Idx < 95);
    AMenuItem.Checked := Idx = ActiveTabIndex + 10;

    FTabPopupMenu.Items.Add(AMenuItem);
  end;

begin
  if FTabPopupMenu <> nil then
    FreeAndNil(FTabPopupMenu);

  FTabPopupMenu := TPopupMenu.Create(nil);

  AddMenuItem(StrNewTab, 3);
  AddMenuItem('-', -1);

  if FMouseDownHitTest.TabIndex <> -1 then
  begin
    AddMenuItem(StrDeleteTab, 2);
    AddMenuItem('-', -1);

    if not Tabs[FMouseDownHitTest.TabIndex].Pinned then
      AddMenuItem(StrPinThisTab, 0)
    else
      AddMenuItem(StrUnpinThisTab, 1);

    AddMenuItem('-', -1);
  end;

  for i := 0 to Tabs.Count - 1 do
    AddMenuItem(GetTabDescription(i), i + 10);

  FTabPopupMenu.Popup(APoint.x, APoint.y);
end;

constructor TCustomChromeTabs.Create(AOwner: TComponent);
begin
  // Make sure that we don't try to draw anything until we're fully loaded
  // State is removed in Loaded override
  AddState(stsLoading);

  inherited;

  if AOwner is TWinControl then
    Parent := TWinControl(AOwner);

  ControlStyle := ControlStyle + [csReplicatable,
                                  csCaptureMouse];

  BeginUpdate; // EndUpdate called in Loaded

  // Canvas Bitmaps
  FCanvasBmp := TBitmap.Create;
  FCanvasBmp.PixelFormat := pf32Bit;

  FBackgroundBmp := TBitmap.Create;
  FBackgroundBmp.PixelFormat := pf32bit;

  // Options
  FLookAndFeel := TChromeTabsLookAndFeel.Create(Self);
  FOptions := TOptions.Create(Self);

  FTabs := TChromeTabsList.Create(Self);

  // Controls
  FAddButtonControl := TAddButtonControl.Create(Self);
  FScrollButtonLeftControl := TScrollButtonLeftControl.Create(Self);
  FScrollButtonRightControl := TScrollButtonRightControl.Create(Self);

  // Timers
  FAnimateTimer := TThreadTimer.Create(Self);
  FAnimateTimer.Interval := FOptions.Animation.AnimationTimerInterval;
  FAnimateTimer.Enabled := TRUE;
  FAnimateTimer.OnTimer := OnAnimateTimer;

  FCancelTabSmartResizeTimer := TTimer.Create(Self);
  FCancelTabSmartResizeTimer.Interval := FOptions.Behaviour.TabSmartDeleteResizeCancelDelay;
  FCancelTabSmartResizeTimer.Enabled := FALSE;
  FCancelTabSmartResizeTimer.OnTimer := OnCancelTabSmartResizeTimer;

  FScrollTimer := TTimer.Create(Self);
  FScrollTimer.Interval := FOptions.Scrolling.ScrollRepeatDelay;
  FScrollTimer.Enabled := FALSE;
  FScrollTimer.OnTimer := OnScrollTimerTimer;

  Width := 300;
  Height := 30;
  FScrollOffset := -1;
  Tabs.ActiveTab := nil;
end;

procedure TCustomChromeTabs.OnCancelTabSmartResizeTimer(Sender: TObject);
begin
  FCancelTabSmartResizeTimer.Enabled := FALSE;

  ClearTabClosingStates;

  AddState(stsControlPositionsInvalidated);

  // Force the tab correction
  FLastClientWidth := -1;
  CorrectScrollOffset;

  Redraw;
end;

procedure TCustomChromeTabs.OnScrollTimerTimer(Sender: TObject);
begin
  if GetTabDisplayState = tdScrolling then
    ScrollTabs(FScrollDirection);
end;

function TCustomChromeTabs.OptionsToCode: String;
var
  TabsOptions: TTabsOptions;
begin
  TabsOptions := TTabsOptions.Create(nil);
  try
    TabsOptions.Options := FOptions;

    Result := ComponentToCode(TabsOptions, DefaultCodeComponentName);
  finally
    FreeAndNil(TabsOptions);
  end;
end;

procedure TCustomChromeTabs.FireScrollTimer;
begin
  OnScrollTimerTimer(FScrollTimer);
end;

procedure TCustomChromeTabs.ScrollTabs(ScrollDirection: TScrollDirection; StartTimer: Boolean);
var
  IncValue: Integer;
begin
  if GetTabDisplayState = tdScrolling then
  begin
    FScrollDirection := ScrollDirection;

    IncValue := FOptions.Scrolling.ScrollStep;

    if BiDiMode in BidiRightToLeftTabModes then
      IncValue := -IncValue;

    case FScrollDirection of
      mdsLeft: ScrollOffset := ScrollOffset - IncValue;
      mdsRight: ScrollOffset := ScrollOffset + IncValue;
    end;

    if StartTimer then
      FScrollTimer.Enabled := TRUE;
  end;
end;

procedure TCustomChromeTabs.OnAnimateTimer(Sender: TObject);

  procedure AnimateButtonControl(ButtonControl: TBaseChromeButtonControl);
  begin
    if ButtonControl.AnimateMovement then
      AddState(stsAnimatingMovement);

    if ButtonControl.AnimateStyle then
      AddState(stsAnimatingStyle);
  end;

var
  i: Integer;
  TickCount: Cardinal;
  AnimateModified: Boolean;
begin
  if not (csDestroying in ComponentState) then
  begin
    RemoveState(stsAnimatingMovement);
    RemoveState(stsAnimatingStyle);

    TickCount := GetTickCount;

    AnimateModified := FNextModifiedGlowAnimateTickCount < TickCount;

    if AnimateModified then
      FNextModifiedGlowAnimateTickCount := TickCount + Cardinal(FOptions.Display.TabModifiedGlow.AnimationUpdateMS);

    for i := pred(Tabs.Count) downto 0 do
    begin
      if (AnimateModified) and
         (TabControls[i].AnimateModified) then
        AddState(stsAnimatingStyle);

      if TabControls[i].AnimateStyle then
        AddState(stsAnimatingStyle);

      if TabControls[i].AnimateMovement then
      begin
        AddState(stsAnimatingMovement);

        if (i = ActiveTabIndex) and (HasState(stsAnimatingNewTab)) then
          ScrollIntoView(Tabs[i]);
      end
      else
      begin
        if (i = ActiveTabIndex) and (HasState(stsAnimatingNewTab)) then
        begin
          RemoveState(stsAnimatingNewTab);

          CorrectScrollOffset(TRUE);

          ScrollIntoView(Tabs[i]);
        end;
      end;

      // We've finshed the delete tab animation. Delete the tab now.
      if Tabs[i].MarkedForDeletion then
      begin
        AddState(stsControlPositionsInvalidated);
        AddState(stsAnimatingMovement);

        if RectWidth(TabControls[i].ControlRect) <= FOptions.Animation.MinimumTabAnimationWidth then
        begin
          DeleteTab(i);

          RemoveState(stsAnimatingCloseTab);
        end;
      end;
    end;

    AnimateButtonControl(FAddButtonControl);
    AnimateButtonControl(FScrollButtonLeftControl);
    AnimateButtonControl(FScrollButtonRightControl);

    if (HasState(stsAnimatingMovement)) or (HasState(stsAnimatingStyle)) then
    begin
      if (HasState(stsDeletingUnPinnedTabs)) and
         (not HasState(stsDragging)) then
        SetControlDrawStates;

      Redraw;
    end;

    { TODO :
      This is a bit of a hack to get the scrolling working for controls on other forms.
      The problem is that while dragging, the message queue of the destination form
      is not processed. }
    if (FDragTabObject <> nil) and
       (FDragTabObject.DockControl <> nil) and
       (FDragTabObject.SourceControl <> FDragTabObject.DockControl) then
      FDragTabObject.DockControl.FireScrollTimer;
  end;
end;

destructor TCustomChromeTabs.Destroy;
begin
  FreeAndNil(FTabs);
  FreeAndNil(FScrollButtonLeftControl);
  FreeAndNil(FScrollButtonRightControl);
  FreeAndNil(FAddButtonControl);
  FreeAndNil(FCanvasBmp);
  FreeAndNil(FBackgroundBmp);
  FreeAndNil(FTabPopupMenu);
  FreeAndNil(FOptions);
  FreeAndNil(FLookAndFeel);

  FActiveDragTabObject := nil;

  inherited;
end;

function TCustomChromeTabs.GetActiveTab: TChromeTab;
begin
  Result := Tabs.ActiveTab;
end;

function TCustomChromeTabs.GetActiveTabIndex: Integer;
begin
  if Tabs.ActiveTab = nil then
    Result := -1
  else
    Result := Tabs.ActiveTab.Index;
end;

function TCustomChromeTabs.GetBiDiMode: TBiDiMode;
begin
  Result := BiDiMode;
end;

function TCustomChromeTabs.GetBidiScrollOffset: Integer;
begin
  if BiDiMode in BidiLeftToRightTabModes then
    Result := FScrollOffset
  else
    Result := -FScrollOffset;
end;

function TCustomChromeTabs.GetComponentState: TComponentState;
begin
  Result := ComponentState;
end;

function TCustomChromeTabs.GetControl: TWinControl;
begin
  Result := Self;
end;

function TCustomChromeTabs.GetImages: TCustomImageList;
begin
  Result := FImages;
end;

function TCustomChromeTabs.GetLastPinnedIndex: Integer;
begin
  Result := GetLastPinnedTabIndex;
end;

function TCustomChromeTabs.GetLastPinnedTabIndex: Integer;
begin
  if (Tabs.Count = 0) or (not Tabs[0].Pinned)then
    Result := -1
  else
  begin
    Result := 0;

    while (Result < FTabs.Count - 1) and (FTabs[Result + 1].Pinned) do
      Inc(Result);
  end;
end;

function TCustomChromeTabs.GetTabControl(Index: Integer): TChromeTabControl;
begin
  if Index = -1 then
    Result := nil
  else
    Result := TChromeTabControl(Tabs[Index].TabControl);
end;

function TCustomChromeTabs.GetTabDescription(Index: Integer): String;
begin
  if (Index >= 0) and
     (Index < Tabs.Count) then
  begin
    Result := Tabs[Index].Caption;

    if Result = '' then
      Result := StrNoCaption;
  end
  else
    Result := '';
end;

function TCustomChromeTabs.GetTabUnderMouse: TChromeTab;
var
  HitTestResult: THitTestResult;
begin
  HitTestResult := HitTest(Point(FLastMouseX, FLastMouseY));

  if HitTestResult.TabIndex = -1 then
    Result := nil
  else
    Result :=  Tabs[HitTestResult.TabIndex];
end;

function TCustomChromeTabs.HitTest(pt: TPoint; IgnoreDisabledControls: Boolean): THitTestResult;
var
  HitTestArea: THitTestArea;
  i: Integer;
begin
  Result.HitTestArea := htBackground;
  Result.TabIndex := -1;

  // Are we even in the container rect?
  if not PtInRect(ControlRect, pt) then
    Result.HitTestArea := htNoWhere else

  // Add button?
  if FAddButtonControl.ContainsPoint(Pt) then
    Result.HitTestArea := htAddButton else
  begin
    // Scroll buttons?
    if (ScrollButtonLeftVisible) and
       ((not IgnoreDisabledControls) or (FScrollButtonLeftControl.DrawState <> dsDisabled)) and
       (FScrollButtonLeftControl.ContainsPoint(pt)) then
      Result.HitTestArea := htScrollButtonLeft else
    begin
      if (ScrollButtonRightVisible) and
         ((not IgnoreDisabledControls) or (FScrollButtonRightControl.DrawState <> dsDisabled)) and
         (FScrollButtonRightControl.ContainsPoint(pt)) then
        Result.HitTestArea := htScrollButtonRight
      else
      begin
        // If we're not overlaying buttons, we need to make sure
        // we're in the tab container
        if (FOptions.Display.TabContainer.OverlayButtons) or
           (PtInRect(TabContainerRect, Pt)) then
        begin
          // Check the active tab first as it will always be in front
          if ActiveTabIndex <> -1 then
          begin
            HitTestArea := TabControls[ActiveTabIndex].GetHitTestArea(pt.x, pt.y);

            if HitTestArea <> htBackground then
            begin
              Result.HitTestArea := HitTestArea;
              Result.TabIndex := ActiveTabIndex;

              Exit;
            end;
          end;

          // Check each tab to see if we have a hit
          for i := 0 to pred(Tabs.Count) do
          begin
            if (not Tabs[i].Visible) or (i = ActiveTabIndex) then
              Continue;

            HitTestArea := TabControls[i].GetHitTestArea(pt.x, pt.y);

            if HitTestArea <> htBackground then
            begin
              Result.HitTestArea := HitTestArea;
              Result.TabIndex := i;

              Break;
            end;
          end;
        end;
      end;
    end;
  end;
end;

procedure TCustomChromeTabs.MouseDown(Button: TMouseButton; Shift: TShiftState; x, y: Integer);
begin
  inherited;

  if not HasState(stsMouseDown) then
  begin
    FMouseDownHitTest := HitTest(Point(x, y));
    FMouseButton := Button;
    FMouseDownPoint := Point(X, Y);

    if (FOptions.Behaviour.BackgroundDragMovesForm) and
       (FMouseDownHitTest.HitTestArea = htBackground) and
       (GetParentForm(Self) <> nil) then
    begin
      ReleaseCapture;

      SendMessage(GetParentForm(Self).Handle, WM_SYSCOMMAND, 61458, 0);
    end else

    begin
      AddState(stsMouseDown);

      SetControlDrawStates(TRUE);

      if FMouseDownHitTest.HitTestArea = htScrollButtonLeft then
      begin
        ScrollTabs(mdsLeft);
      end else

      if FMouseDownHitTest.HitTestArea = htScrollButtonRight then
      begin
        ScrollTabs(mdsRight);
      end else

      begin
        BeginUpdate;
        try
          if CanFocus then
            SetFocus;

          if (Button = mbLeft) or
             ((Button = mbRight) and
              (FOptions.Behaviour.TabRightClickSelect)) then
          begin
            // Are activvating a tab?
            if ((FMouseDownHitTest.HitTestArea = htTab) or
                ((FMouseDownHitTest.HitTestArea = htCloseButton) and (Button = mbRight))) and
               (FMouseDownHitTest.TabIndex <> ActiveTabIndex) then
            begin
              Tabs[FMouseDownHitTest.TabIndex].Active := TRUE;
            end;
          end;
        finally
          EndUpdate;
        end;
      end;
    end;

    //Redraw;
  end;
end;

procedure TCustomChromeTabs.CMHintShow(var Message: TCMHintShow);
var
  HitTestResult: THitTestResult;
  HintText: String;
  HintTimeout: Integer;
  HintRect: TRect;
begin
  Message.Result := 1;

  if HasState(stsDragging) then
    inherited
  else
  begin
    HitTestResult := HitTest(Message.HintInfo.CursorPos);
    HintText := GetTabDescription(HitTestResult.TabIndex);
    HintTimeout := 5000;

    DoOnShowHint(HitTestResult, HintText, HintTimeout);

    if HintText = '' then
      inherited
    else
    begin
      if HitTestResult.TabIndex <> -1 then
        HintRect := TabControls[HitTestResult.TabIndex].ControlRect
      else
        HintRect := ControlRect;

      Message.HintInfo.HintStr := HintText;
      Message.HintInfo.CursorRect := HintRect;
      Message.HintInfo.HideTimeout := HintTimeout;
      //Message.HintInfo.HintPos := ClientToScreen(Point(FLastMouseX, FLastMouseY));
      Message.Result := 0;
    end;
  end;
end;

function TCustomChromeTabs.BidiRect(ARect: TRect): TRect;
begin
  if BiDiMode in BidiRightToLeftTabModes then
    Result := HorzFlipRect(ControlRect, ARect)
  else
    Result := ARect;
end;

function TCustomChromeTabs.BidiXPos(X: Integer): Integer;
begin
  if BiDiMode in BidiRightToLeftTextModes then
    Result := ClientWidth - X
  else
    Result := X;
end;

procedure TCustomChromeTabs.MouseMove(Shift: TShiftState; x, y: Integer);
var
  HitTestResult: THitTestResult;
  DragTabControl: TChromeTabControl;
  AllowDrag: Boolean;
  CursorWinControl: TWinControl;
  TabDockControl, PreviousDockControl: IChromeTabDockControl;
  Accept, DummyAccept: Boolean;
  ScreenPoint, ControlPoint: TPoint;
begin
  inherited;

  if (FLastMouseX <> X) or
     (FLastMouseY <> Y) then
  begin
    FLastMouseX := X;
    FLastMouseY := Y;

    BeginUpdate;
    try
      HitTestResult := HitTest(Point(X, Y));

      // Are we ready to start dragging?
      if (not (HasState(stsDragging))) and
         (FOptions.DragDrop.DragType in [dtWithinContainer, dtBetweenContainers]) and
         (HasState(stsMouseDown)) and
         (FMouseDownHitTest.HitTestArea = htTab) and
         (FMouseButton = mbLeft) and
         (HitTestResult.HitTestArea = htTab) and
         ((FMouseDownPoint.X >= x + FOptions.DragDrop.DragStartPixels) or
          (FMouseDownPoint.X <= x - FOptions.DragDrop.DragStartPixels) or
          (FMouseDownPoint.Y >= y + FOptions.DragDrop.DragStartPixels) or
          (FMouseDownPoint.Y <= y - FOptions.DragDrop.DragStartPixels)) then
      begin
        AllowDrag := TRUE;

        DoOnBeginTabDrag(FTabs[HitTestResult.TabIndex], AllowDrag);

        if AllowDrag then
          BeginDrag(FMouseDownPoint.X, FMouseDownPoint.Y);
      end;

      if FDragTabObject = nil then
        SetControlDrawStates;

      // Are we dragging? Yes, move the drag tab
      if (FDragTabObject <> nil) and
         (FDragTabObject.SourceControl.GetControl = Self) then
      begin
        DragTabControl := TabControls[FDragTabObject.DragTab.Index];

        // Note that we only set the position of the tab, the index doesn't change.
        // We will move the tab to a new index when the MouseUp event
        SetControlLeft(DragTabControl,
                       BidiXPos(X - FDragTabObject.DragCursorOffset.X),
                       FALSE); // Never animate beacause we're dragging

        if FOptions.DragDrop.DragType = dtWithinContainer then
        begin
          TabDragOver(Self, X, Y, dsDragMove, FDragTabObject, DummyAccept);
        end
        else
        begin
          ScreenPoint := Mouse.CursorPos;

          // Find the VCL Control under the cursor
          CursorWinControl := FindChromeTabsControlWithinRange(ScreenPoint, FOptions.DragDrop.DragOutsideDistancePixels);

          Accept := FALSE;

          if CursorWinControl = nil then
            DoOnDebugLog('No ChromeTabs found at X: %d, Y: %d', [ScreenPoint.X, ScreenPoint.Y])
          else
            DoOnDebugLog('ChromeTabs (%s) found at X: %d, Y: %d', [CursorWinControl.Name, ScreenPoint.X, ScreenPoint.Y]);

          // Does it support IChromeTabDockControl?
          if Supports(CursorWinControl, IChromeTabDockControl, TabDockControl) then
          begin
            Accept := TRUE;

            ControlPoint := TabDockControl.GetControl.ScreenToClient(ScreenPoint);

            // Tell the dock control that we are dragging over it
            if (FDragTabObject.DockControl = nil) or
               (FDragTabObject.DockControl.GetControl <> Self) then
              TabDockControl.TabDragOver(Self, ControlPoint.X, ControlPoint.Y, dsDragEnter, FDragTabObject, Accept);

            if Accept then
            begin
              PreviousDockControl := FDragTabObject.DockControl;

              // Set the current dock control
              FDragTabObject.DockControl := TabDockControl;

              // If the current drag object is nil we need to tell the new dock control
              // that we're starting to drag over it.
              if (PreviousDockControl <> nil) and
                 (PreviousDockControl <> TabDockControl) then
                TabDockControl.TabDragOver(Self, ControlPoint.X, ControlPoint.Y, dsDragLeave, FDragTabObject, DummyAccept);

              TabDockControl.TabDragOver(Self, ControlPoint.X, ControlPoint.Y, dsDragMove, FDragTabObject, DummyAccept);

              // Redraw if we're dragging a tab over our container
              if (FDragTabObject.DockControl <> nil) and
                 (FDragTabObject.DockControl.GetControl = FDragTabObject.SourceControl.GetControl) then
                Redraw;
            end;
          end
          else
          begin
            // If we were over a dock control, we need to tell it that we've leaving
            if FDragTabObject.DockControl <> nil then
            begin
              ControlPoint := FDragTabObject.DockControl.GetControl.ScreenToClient(ScreenPoint);

              FDragTabObject.DockControl.TabDragOver(Self, ControlPoint.X, ControlPoint.Y, dsDragLeave, FDragTabObject, DummyAccept);
            end;

            // Clear the current dock control
            FDragTabObject.DockControl := nil;
          end;

          // Show the drag form if required
          ShowTabDragForm(X, Y, not Accept);
        end;

        // Remove the drag start state
        RemoveState(stsDragStarted);
      end
      else
      begin
        // Force a redraw if we're drawing the mouse glow
        if (FOptions.Display.TabMouseGlow.Visible) and (HitTestResult.HitTestArea in [htTab, htCloseButton]) then
          Redraw;
      end;
    finally
      EndUpdate;
    end;
  end;
end;

function TCustomChromeTabs.CreateDragForm(ATab: TChromeTab): TForm;
const
  TransparentColor = clWhite - $100;
var
  DragControl: TWinControl;
  DragCanvas: TGPGraphics;
  Bitmap, ScaledBitmap: TBitmap;
  TempRect: TRect;
  TabTop, ControlTop, TabEndX, BorderOffset: Integer;
  ActualDragDisplay: TChromeTabDragDisplay;
  BorderPen: TGPPen;
  BiDiX: Integer;
begin
  Result := nil;
  DragControl := nil;

  if FOptions.DragDrop.DragDisplay in [ddTab, ddControl, ddTabAndControl] then
  begin
    ActualDragDisplay := FOptions.DragDrop.DragDisplay;

    DoOnCreateDragForm(ATab, Result);

    if Result = nil then
    begin
      if ActualDragDisplay in [ddControl, ddTabAndControl] then
      begin
        DoOnNeedDragImageControl(ATab, DragControl);

        if DragControl = nil then
          ActualDragDisplay := ddTab;
      end;

      if BiDiMode in BidiRightToLeftTabModes then
        BiDiX := ControlRect.Right + FDragTabObject.DragCursorOffset.X
      else
        BiDiX := FDragTabObject.DragCursorOffset.X;

      FDragTabObject.DragFormOffset := Point(Round(BiDiX * FOptions.DragDrop.DragControlImageResizeFactor),
                                             Round(FDragTabObject.DragCursorOffset.Y * FOptions.DragDrop.DragControlImageResizeFactor));

      Bitmap := TBitmap.Create;
      try
        TabTop := 0;
        ControlTop := 0;
        TabEndX := 0;

        case ActualDragDisplay of
          ddTab:
            begin
              Bitmap.Height := RectHeight(TabControls[ATab.Index].ControlRect);
              Bitmap.Width := RectWidth(TabControls[ATab.Index].ControlRect);
            end;

          ddControl:
            begin
              Bitmap.Height := DragControl.Height;
              Bitmap.Width := DragControl.Width;
            end;

          else
          begin
            Bitmap.Height := RectHeight(TabControls[ATab.Index].ControlRect) + DragControl.Height;
            Bitmap.Width := DragControl.Width;
            TabEndX := RectWidth(TabControls[ATab.Index].ControlRect);

            case FOptions.Display.Tabs.Orientation of
              toTop:
                begin
                  ControlTop := RectHeight(TabControls[ATab.Index].ControlRect);
                end;

              toBottom:
                begin
                  TabTop := DragControl.Height - 1;
                  FDragTabObject.DragFormOffset := Point(FDragTabObject.DragFormOffset.X,
                                                         FDragTabObject.DragFormOffset.Y + Round(DragControl.Height * FOptions.DragDrop.DragControlImageResizeFactor));
                end;
            end;
          end;
        end;

        // Copy the control to the bitmap
        if ActualDragDisplay in [ddControl, ddTabAndControl] then
          CopyControlToBitmap(DragControl, Bitmap, 0, ControlTop);

        DragCanvas := TGPGraphics.Create(Bitmap.Canvas.Handle);
        try
          if ActualDragDisplay in [ddTab, ddTabAndControl] then
          begin
            // Draw a background for the tab. This will be made transparent later
            Bitmap.Canvas.Brush.Color := TransparentColor;

            case FOptions.Display.Tabs.Orientation of
              toTop: Bitmap.Canvas.FillRect(Rect(0, 0, Bitmap.Width, ControlTop - 1));
              toBottom: Bitmap.Canvas.FillRect(Rect(0, Bitmap.Height, Bitmap.Width, TabTop));
            end;

            // Do the painting...
            DragCanvas.SetSmoothingMode(FOptions.Display.Tabs.CanvasSmoothingMode);

            TabControls[ATab.Index].ScrollableControl := FALSE;
            TempRect := TabControls[ATab.Index].ControlRect;
            try
              if (ActualDragDisplay in [ddControl, ddTabAndControl]) and (RectWidth(TabControls[ATab.Index].ControlRect) > DragControl.Width - 10) then
                TabControls[ATab.Index].SetWidth(DragControl.Width - 10, 0, ttNone);

              SetControlPosition(TabControls[ATab.Index],
                                 Rect(0,
                                      TabTop,
                                      TabControls[ATab.Index].ControlRect.Right - TabControls[ATab.Index].ControlRect.Left,
                                      TabTop + RectHeight(TabControls[ATab.Index].ControlRect)),
                                      FALSE);

              TabControls[ATab.Index].DrawTo(DragCanvas, FLastMouseX, FLastMouseY);
            finally
              TabControls[ATab.Index].ScrollableControl := TRUE;

              SetControlPosition(TabControls[ATab.Index],
                                 TempRect,
                                 FALSE);
            end;
          end;

          if ActualDragDisplay in [ddControl, ddTabAndControl] then
          begin
            BorderPen := TGPPen.Create(MakeGDIPColor(FOptions.DragDrop.DragFormBorderColor, 255), FOptions.DragDrop.DragFormBorderWidth);
            try
              BorderOffset := FOptions.DragDrop.DragFormBorderWidth div 2;

              case FOptions.Display.Tabs.Orientation of
                toTop:
                  begin
                    DragCanvas.DrawLine(BorderPen, TabEndX, ControlTop, Bitmap.Width - BorderOffset, ControlTop);
                    DragCanvas.DrawLine(BorderPen, Bitmap.Width - BorderOffset, ControlTop, Bitmap.Width - BorderOffset, Bitmap.Height - BorderOffset);
                    DragCanvas.DrawLine(BorderPen, Bitmap.Width - BorderOffset, Bitmap.Height - BorderOffset, 0, Bitmap.Height - BorderOffset);
                    DragCanvas.DrawLine(BorderPen, 0, Bitmap.Height - BorderOffset, 0, ControlTop);
                  end;

                toBottom:
                  begin
                    { TODO : Needs fixing for bottom tabs }
                    DragCanvas.DrawLine(BorderPen, TabEndX, ControlTop, Bitmap.Width - BorderOffset, ControlTop);
                    DragCanvas.DrawLine(BorderPen, Bitmap.Width - BorderOffset, ControlTop, Bitmap.Width - BorderOffset, Bitmap.Height - BorderOffset);
                    DragCanvas.DrawLine(BorderPen, Bitmap.Width - BorderOffset, Bitmap.Height - BorderOffset, 0, Bitmap.Height - BorderOffset);
                    DragCanvas.DrawLine(BorderPen, 0, Bitmap.Height - BorderOffset, 0, ControlTop);
                  end;
              end;
            finally
              FreeAndNil(BorderPen);
            end;
          end;
        finally
          FreeAndNil(DragCanvas);
        end;

        ScaledBitmap := TBitmap.Create;
        try
          // Scale the image
          ScaleImage(Bitmap, ScaledBitmap, FOptions.DragDrop.DragControlImageResizeFactor);

          // Convert the bitmap to a 32bit bitmap
          BitmapTo32BitBitmap(ScaledBitmap);

          // Make the tab background colour transparent
          SetColorAlpha(ScaledBitmap, TransparentColor, 0);

          // Create the alpha blend form
          Result := CreateAlphaBlendForm(Self, ScaledBitmap, FOptions.DragDrop.DragOutsideImageAlpha);

          Result.BorderStyle := bsNone;
        finally
          FreeAndNil(ScaledBitmap);
        end;
      finally
        FreeAndNil(Bitmap);
      end;
    end;
  end;
end;

procedure TCustomChromeTabs.DoOnButtonAddClick;
begin
  if Assigned(FOnButtonAddClick) then
    FOnButtonAddClick(Self);
end;

procedure TCustomChromeTabs.DoOnCreateDragForm(ATab: TChromeTab;
  var DragForm: TForm);
begin
  if Assigned(FOnCreateDragForm) then
    FOnCreateDragForm(Self, ATab, DragForm);
end;

procedure TCustomChromeTabs.DoOnDebugLog(const Text: String; Args: Array of const);
begin
  if (FOptions.Behaviour.DebugMode) and (Assigned(FOnDebugLog)) then
    FOnDebugLog(Self, format(Text, Args));
end;

procedure TCustomChromeTabs.DoOnGetControlPolygons(ItemRect: TRect;
  ItemType: TChromeTabItemType; Orientation: TTabOrientation; var Polygons: IChromeTabPolygons);
begin
  if Assigned(FOnGetControlPolygons) then
    FOnGetControlPolygons(Self, ItemRect, ItemType, Orientation, Polygons);
end;

procedure TCustomChromeTabs.DoOnNeedDragImageControl(ATab: TChromeTab;
  var DragControl: TWinControl);
begin
  if Assigned(FOnNeedDragImageControl) then
    FOnNeedDragImageControl(Self, ATab, DragControl);
end;

procedure TCustomChromeTabs.DoOnScroll;
begin
  if Assigned(FOnScroll) then
    FOnScroll(Self);
end;

procedure TCustomChromeTabs.DoOnShowHint(HitTestResult: THitTestResult;
  var HintText: String; var HintTimeout: Integer);
begin
  if Assigned(FOnShowHint) then
    FOnShowHint(Self, HitTestResult, HintText, HintTimeout);
end;

procedure TCustomChromeTabs.DoOnStateChange(PreviousState,
  CurrentState: TChromeTabStates);
begin
  if Assigned(FOnStateChange) then
    FOnStateChange(Self, PreviousState, CurrentState);
end;

procedure TCustomChromeTabs.DoOnScrollWidthChanged;
begin
  if Assigned(FOnScrollWidthChanged) then
    FOnScrollWidthChanged(Self);
end;

procedure TCustomChromeTabs.DoOnTabDblClick(ATab: TChromeTab);
begin
  if Assigned(FOnTabDblClick) then
    FOnTabDblClick(Self, ATab);
end;

procedure TCustomChromeTabs.DoOnTabDragDrop(X, Y: Integer; DragTabObject: IDragTabObject; Cancelled: Boolean;
  var TabDropOptions: TTabDropOptions);
begin
  if Assigned(FOnTabDragDrop) then
    FOnTabDragDrop(Self, X, Y, DragTabObject, Cancelled, TabDropOptions);
end;

procedure TCustomChromeTabs.DoOnTabDragDropped(DragTabObject: IDragTabObject;
  NewTab: TChromeTab);
begin
  if Assigned(FOnTabDragDropped) then
    FOnTabDragDropped(Self, DragTabObject, NewTab);
end;

procedure TCustomChromeTabs.DoOnTabDragOver(X, Y: Integer; State: TDragState;
  DragTabObject: IDragTabObject; var Accept: Boolean);
begin
  if Assigned(FOnTabDragOver) then
    FOnTabDragOver(Self, X, Y, State, DragTabObject, Accept);
end;

procedure TCustomChromeTabs.DoOnTabDragStart(ATab: TChromeTab;
  var Allow: Boolean);
begin
  if Assigned(FOnTabDragStart) then
    FOnTabDragStart(Self, ATab, Allow);
end;

procedure TCustomChromeTabs.MouseUp(Button: TMouseButton; Shift: TShiftState; x, y: Integer);
var
  AllowClose: Boolean;
  HitTestResult: THitTestResult;
begin
  inherited;

  BeginUpdate;
  try
    FScrollTimer.Enabled := FALSE;

    RemoveState(stsMouseDown);

    HitTestResult := HitTest(Point(X, Y));

    if HasState(stsDragging) then
    begin
      EndDrag(X, Y, FDragCancelled);
    end;

    if (HitTestResult.HitTestArea = htAddButton) and
       (FMouseDownHitTest.HitTestArea = htAddButton) then
    begin
      DoOnButtonAddClick;

      AddState(stsControlPositionsInvalidated);
    end else

    // Have we clicked the Close button?
    if (FMouseButton = mbLeft) and
       (HitTestResult.HitTestArea = htCloseButton) and
       (FMouseDownHitTest.HitTestArea = htCloseButton) and
       (HitTestResult.TabIndex = FMouseDownHitTest.TabIndex) then
    begin
      AllowClose := TRUE;

      DoOnButtonCloseTabClick(Tabs[HitTestResult.TabIndex], AllowClose);

      // Only close if the user has allowed it
      if AllowClose then
      begin
        // If we're closing the tab via the close button we need to realign the
        // tabs so the next tab's close button is under the cursor.
        if not Tabs[HitTestResult.TabIndex].Pinned then
        begin
          // Reset the tab closing state
          ClearTabClosingStates;

          AddState(stsDeletingUnPinnedTabs);

          FClosedTabRect := TabControls[HitTestResult.TabIndex].EndRect;
          FClosedTabIndex := HitTestResult.TabIndex;
        end;

        DeleteTab(HitTestResult.TabIndex);

        AddState(stsControlPositionsInvalidated);
      end;
    end;

    SetControlDrawStates(TRUE);

    Redraw;
  finally
    EndUpdate;
  end;
end;

procedure TCustomChromeTabs.DoOnAfterDrawItem(const TargetCanvas: TGPGraphics;
  ItemRect: TRect; ItemType: TChromeTabItemType; TabIndex: Integer);
begin
  if Assigned(FOnAfterDrawItem) then
    FOnAfterDrawItem(Self, TargetCanvas, ItemRect, ItemType, TabIndex);
end;

procedure TCustomChromeTabs.DoOnBeforeDrawItem(TargetCanvas: TGPGraphics;
  ItemRect: TRect; ItemType: TChromeTabItemType; TabIndex: Integer;
  var Handled: Boolean);
begin
  Handled := FALSE;

  if Assigned(FOnBeforeDrawItem) then
    FOnBeforeDrawItem(Self, TargetCanvas, ItemRect, ItemType, TabIndex, Handled);
end;

procedure TCustomChromeTabs.DoOnBeginTabDrag(ATab: TChromeTab;
  var Allow: Boolean);
begin
  if Assigned(FOnBeginTabDrag) then
    FOnBeginTabDrag(Self, ATab, Allow);
end;

procedure TCustomChromeTabs.DoOnButtonCloseTabClick(ATab: TChromeTab; var AllowClose: Boolean);
begin
  if Assigned(FOnButtonCloseTabClick) then
    FOnButtonCloseTabClick(Self, ATab, AllowClose);
end;

procedure TCustomChromeTabs.Notification(AComponent: TComponent;
  Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);

  if (Operation = opRemove) then
  begin
    if AComponent = FImages then
      SetImages(nil) else

    if AComponent = FImagesOverlay then
      SetImagesOverlay(nil);
  end;
end;

procedure TCustomChromeTabs.WMLButtonDblClk(var Message: TWMLButtonDblClk);
var
  HitTestResult: THitTestResult;
  ParentForm: TCustomForm;
begin
  if (not FOptions.Behaviour.IgnoreDoubleClicksWhileAnimatingMovement) or
     (not HasState(stsAnimatingMovement)) then
  begin
    HitTestResult := HitTest(Point(Message.XPos, Message.YPos));

    if HitTestResult.TabIndex <> -1 then
      DoOnTabDblClick(FTabs[HitTestResult.TabIndex]);

    if FOptions.Behaviour.BackgroundDblClickMaximiseRestoreForm then
    begin
      if HitTestResult.HitTestArea = htBackground then
      begin
        ParentForm := GetParentForm(Self);

        if ParentForm <> nil then
        begin
          if ParentForm.WindowState = wsNormal then
            ParentForm.WindowState := wsMaximized
          else
            ParentForm.WindowState := wsNormal;
        end;
      end;
    end;
  end;
end;

procedure TCustomChromeTabs.SaveLookAndFeel(Stream: TStream);
var
  TabsLookAndFeel: TTabsLookAndFeel;
begin
  TabsLookAndFeel := TTabsLookAndFeel.Create(nil);
  try
    TabsLookAndFeel.LookAndFeel := FLookAndFeel;

    SaveComponentToStream(TabsLookAndFeel, Stream);
  finally
    FreeAndNil(TabsLookAndFeel);
  end;
end;

procedure TCustomChromeTabs.SaveLookAndFeel(const Filename: String);
var
  FileStream: TFileStream;
begin
  if FileExists(Filename) then
    DeleteFile(Filename);

  FileStream := TFileStream.Create(Filename, fmCreate);
  try
    SaveLookAndFeel(FileStream);
  finally
    FreeAndNil(FileStream);
  end;
end;

procedure TCustomChromeTabs.SaveOptions(const Filename: String);
var
  FileStream: TFileStream;
begin
  if FileExists(Filename) then
    DeleteFile(Filename);

  FileStream := TFileStream.Create(Filename, fmCreate);
  try
    SaveOptions(FileStream);
  finally
    FreeAndNil(FileStream);
  end;
end;

procedure TCustomChromeTabs.SaveOptions(Stream: TStream);
var
  TabsOptions: TTabsOptions;
begin
  TabsOptions := TTabsOptions.Create(nil);
  try
    TabsOptions.Options := FOptions;

    SaveComponentToStream(TabsOptions, Stream);
  finally
    FreeAndNil(TabsOptions);
  end;
end;

function TCustomChromeTabs.ScrollButtonLeftVisible: Boolean;
begin
  Result := ((ScrollingActive) or (not FOptions.Scrolling.AutoHideButtons)) and
            (FOptions.Scrolling.Enabled);
end;

function TCustomChromeTabs.ScrollButtonRightVisible: Boolean;
begin
  Result := ((ScrollingActive) or (not FOptions.Scrolling.AutoHideButtons)) and
            (FOptions.Scrolling.Enabled);
end;

procedure TCustomChromeTabs.CalculateRects;
var
  RightOffset, LeftOffset, ScrollDelta: Integer;
begin
  // Add the left offset first
  LeftOffset := FOptions.Display.TabContainer.PaddingLeft;
  RightOffset := CorrectedClientWidth - FOptions.Display.TabContainer.PaddingRight;

  // Clear Rects
  SetControlPosition(FScrollButtonLeftControl, Rect(0,0,0,0), FALSE);
  SetControlPosition(FScrollButtonRightControl, Rect(0,0,0,0), FALSE);
  SetControlPosition(FAddButtonControl, Rect(0,0,0,0), FALSE);

  // Calculate the left offset
  if (ScrollButtonLeftVisible) and
     (FOptions.Scrolling.ScrollButtons in [csbLeft, csbLeftAndRight]) then
  begin
    SetControlPosition(FScrollButtonLeftControl,
                       Rect(LeftOffset + FOptions.Display.ScrollButtonLeft.Offsets.Horizontal,
                            FOptions.Display.ScrollButtonLeft.Offsets.Vertical,
                            LeftOffset + FOptions.Display.ScrollButtonLeft.Offsets.Horizontal + FOptions.Display.ScrollButtonLeft.Width,
                            FOptions.Display.ScrollButtonLeft.Offsets.Vertical + FOptions.Display.ScrollButtonLeft.Height),
                            FALSE);

    Inc(LeftOffset, RectWidth(FScrollButtonLeftControl.ControlRect) + FOptions.Display.ScrollButtonLeft.Offsets.Horizontal + 1);
  end;

  // If the scroll Right button is visible on the left, calculate it's rect
  if (ScrollButtonRightVisible) and
     (FOptions.Scrolling.ScrollButtons in [csbLeft]) then
  begin
    SetControlPosition(FScrollButtonRightControl,
                       Rect(LeftOffset + FOptions.Display.ScrollButtonRight.Offsets.Horizontal,
                            FOptions.Display.ScrollButtonRight.Offsets.Vertical,
                            LeftOffset + FOptions.Display.ScrollButtonRight.Offsets.Horizontal + FOptions.Display.ScrollButtonRight.Width,
                            FOptions.Display.ScrollButtonRight.Offsets.Vertical + FOptions.Display.ScrollButtonRight.Height),
                       FALSE);

    Inc(LeftOffset, RectWidth(FScrollButtonRightControl.ControlRect) + FOptions.Display.ScrollButtonRight.Offsets.Horizontal + 1);
  end;

  if FOptions.Display.AddButton.Visibility in [avLeft] then
  begin
    SetControlPosition(FAddButtonControl,
                       Rect(LeftOffset + FOptions.Display.AddButton.Offsets.Horizontal,
                            FOptions.Display.AddButton.Offsets.Vertical,
                            LeftOffset + FOptions.Display.AddButton.Offsets.Horizontal + FOptions.Display.AddButton.Width,
                            FOptions.Display.AddButton.Height + FOptions.Display.AddButton.Offsets.Vertical),
                       FALSE);

    Inc(LeftOffset, FOptions.Display.AddButton.Width + FOptions.Display.AddButton.Offsets.Horizontal + 1);
  end;

  // Calculate the right offset
  if (ScrollButtonRightVisible) and
     (FOptions.Scrolling.ScrollButtons in [csbRight, csbLeftAndRight]) then
  begin
    SetControlPosition(FScrollButtonRightControl,
                       Rect(RightOffset - FOptions.Display.ScrollButtonRight.Width - FOptions.Display.ScrollButtonRight.Offsets.Horizontal,
                            FOptions.Display.ScrollButtonRight.Offsets.Vertical,
                            RightOffset - FOptions.Display.ScrollButtonRight.Offsets.Horizontal,
                            FOptions.Display.ScrollButtonRight.Offsets.Vertical + FOptions.Display.ScrollButtonRight.Height),
                       FALSE);

    Dec(RightOffset, RectWidth(FScrollButtonRightControl.ControlRect) + 1 + FOptions.Display.ScrollButtonRight.Offsets.Horizontal);
  end;

  if (ScrollButtonLeftVisible) and
     (FOptions.Scrolling.ScrollButtons in [csbRight]) then
  begin
    SetControlPosition(FScrollButtonLeftControl,
                       Rect(RightOffset - FOptions.Display.ScrollButtonLeft.Width - FOptions.Display.ScrollButtonLeft.Offsets.Horizontal,
                            FOptions.Display.ScrollButtonLeft.Offsets.Vertical,
                            RightOffset - FOptions.Display.ScrollButtonLeft.Offsets.Horizontal,
                            FOptions.Display.ScrollButtonLeft.Offsets.Vertical + FOptions.Display.ScrollButtonLeft.Height),
                       FALSE);

    Dec(RightOffset, RectWidth(FScrollButtonLeftControl.ControlRect) + 1 + FOptions.Display.ScrollButtonLeft.Offsets.Horizontal);
  end;

  if (FOptions.Display.AddButton.Visibility = avRightFixed) or
     (FOptions.Display.AddButton.Visibility = avRightFloating) then
  begin
    FMaxAddButtonRight := RightOffset - FOptions.Display.AddButton.Width - FOptions.Display.AddButton.Offsets.Horizontal;

    if FOptions.Display.AddButton.Visibility <> avRightFloating then
      SetControlPosition(FAddButtonControl,
                         Rect(FMaxAddButtonRight,
                              FOptions.Display.AddButton.Offsets.Vertical,
                              RightOffset - FOptions.Display.AddButton.Offsets.Horizontal,
                              FOptions.Display.AddButton.Height + FOptions.Display.AddButton.Offsets.Vertical),
                         FALSE);

    Dec(RightOffset, FOptions.Display.AddButton.Width + 1 + FOptions.Display.AddButton.Offsets.Horizontal);
  end;

  // Remaining space is the TabContainerRect
  if (FOptions.Behaviour.TabSmartDeleteResizing) and
     (HasState(stsDeletingUnPinnedTabs)) and
     (HasState(stsEndTabDeleted)) then
  begin
    ScrollDelta := FScrollOffset;

    FScrollOffset := FScrollOffset - RectWidth(FClosedTabRect) + FOptions.Display.Tabs.TabOverlap;

    if FScrollOffset < 0 then
      FScrollOffset := 0;

    ScrollDelta := ScrollDelta - FScrollOffset;

    FTabContainerRect := Rect(LeftOffset + FOptions.Display.Tabs.OffsetLeft,
                              FOptions.Display.Tabs.OffsetTop,
                              FClosedTabRect.Right - ScrollDelta,
                              ClientHeight - FOptions.Display.Tabs.OffsetBottom);
  end
  else
  begin
    FTabContainerRect := Rect(LeftOffset + FOptions.Display.Tabs.OffsetLeft,
                              FOptions.Display.Tabs.OffsetTop,
                              RightOffset - FOptions.Display.Tabs.OffsetRight,
                              ClientHeight - FOptions.Display.Tabs.OffsetBottom);
  end;
end;

function TCustomChromeTabs.ScrollingActive: Boolean;
begin
  Result := FScrollWidth - FTabEndSpace > CorrectedClientWidth
end;

function TCustomChromeTabs.SameBidiTabMode(BidiMode1, BiDiMode2: TBidiMode): Boolean;
begin
  Result := ((BidiMode1 in BidiRightToLeftTabModes) and
             (BidiMode2 in BidiRightToLeftTabModes)) or
             ((BidiMode1 in BidiLeftToRightTabModes) and
             (BidiMode2 in BidiLeftToRightTabModes));
end;

procedure TCustomChromeTabs.SetControlPosition(ChromeTabsControl: TBaseChromeTabsControl; ControlRect: TRect; Animate: Boolean);
var
  EaseType: TChromeTabsEaseType;
  AnimationTime: Cardinal;
begin
  if (Animate) and (not (csDesigning in ComponentState)) then
  begin
    EaseType := FMovementEaseType;
    AnimationTime := FMovementAnimationTime;
  end
  else
  begin
    EaseType := ttNone;
    AnimationTime := 0;
  end;

  if not (csDesigning in ComponentState) then
    DoOnAnimateMovement(ChromeTabsControl, AnimationTime, EaseType);

  ChromeTabsControl.SetPosition(ControlRect,
                                AnimationTime,
                                EaseType);
end;

procedure TCustomChromeTabs.SetControlLeft(ChromeTabsControl: TBaseChromeTabsControl; ALeft: Integer; Animate: Boolean);
begin
  SetControlPosition(ChromeTabsControl,
                     Rect(ALeft,
                          ChromeTabsControl.ControlRect.Top,
                          RectWidth(ChromeTabsControl.ControlRect) + ALeft,
                          ChromeTabsControl.ControlRect.Bottom),
                     Animate);
end;

procedure TCustomChromeTabs.SetMovementAnimation(MovementAnimationTypes: TChromeTabsMovementAnimationTypes);
begin
  if MovementAnimationTypes = nil then
  begin
    FMovementEaseType := ttNone;
    FMovementAnimationTime := 0;
  end
  else
  begin
    FMovementEaseType := FOptions.Animation.GetMovementAnimationEaseType(MovementAnimationTypes);
    FMovementAnimationTime := FOptions.Animation.GetMovementAnimationTime(MovementAnimationTypes);
  end;
end;

procedure TCustomChromeTabs.RepositionTabs;

  procedure CalculateAverageTabWidth(var TabWidth, TabEndSpace: Integer);
  var
    VisibleTabCount, PinnedTabWidth: Integer;
    TabClientWidth: Integer;
    TabClientRect: TRect;
    VisiblePinnedTabCount: Integer;
  begin
    TabEndSpace := 0;

    TabClientRect := TabContainerRect;

    VisiblePinnedTabCount := GetVisiblePinnedTabCount;

    if (FDragTabControl <> nil) and
       (FActiveDragTabObject.SourceControl.GetControl <> Self) and
       (FActiveDragTabObject.DragTab.Pinned) then
      VisiblePinnedTabCount := VisiblePinnedTabCount + 1;

    VisibleTabCount := GetVisibleNonPinnedTabCount;

    if (FDragTabControl <> nil) and
       (FActiveDragTabObject.SourceControl.GetControl <> Self) and
       (not FActiveDragTabObject.DragTab.Pinned) then
      VisibleTabCount := VisibleTabCount + 1;

    PinnedTabWidth := VisiblePinnedTabCount * FOptions.Display.Tabs.PinnedWidth;
    TabClientWidth := RectWidth(TabClientRect) - PinnedTabWidth - FOptions.Display.Tabs.TabOverlap;

    if FDragTabControl <> nil then
      TabClientWidth := TabClientWidth + FOptions.Display.Tabs.TabOverlap;

    if VisibleTabCount > 0 then
    begin
      TabWidth := TabClientWidth div VisibleTabCount;
      TabEndSpace := TabClientWidth mod VisibleTabCount;
    end
    else
      TabWidth := 0;

    if TabWidth < FOptions.Display.Tabs.MinWidth then
    begin
      TabWidth := FOptions.Display.Tabs.MinWidth;
      TabEndSpace := 0;
    end;

    if TabWidth > FOptions.Display.Tabs.MaxWidth then
    begin
      TabWidth := FOptions.Display.Tabs.MaxWidth;

      TabEndSpace := 0;
    end;
  end;

  procedure SetTabPositionsClosing(var TabLeft: Integer);
  var
    i, TabWidth: Integer;
    TabControl: TChromeTabControl;
    RealClosedTabIndex: Integer;
  begin
    for i := 0 to pred(Tabs.Count) do
    begin
      if (not FTabs[i].Visible) or
         (i < FClosedTabIndex) then
        Continue;

      // Find the actual tab control
      TabControl := TabControls[i];

      RealClosedTabIndex := FClosedTabIndex;

      // If we're animating, the deleted tab still exists
      if (FOptions.Animation.GetMovementAnimationEaseType(FOptions.Animation.MovementAnimations.TabDelete) <> ttNone) and
         (HasState(stsAnimatingCloseTab)) then
        Inc(RealClosedTabIndex);

      if i = RealClosedTabIndex then
      begin
        // Make sure the new tab at this position is exactly the same as
        // the one that was just closed
        TabWidth := RectWidth(FClosedTabRect);
        TabLeft := FClosedTabRect.Left;
      end
      else
        TabWidth := RectWidth(TabControls[i].ControlRect);

      if not Tabs[i].MarkedForDeletion then
      begin
        // Set the position of the tabs
        //SetMovementAnimation(FOptions.Animation.MovementAnimations.TabMove);

        SetControlPosition(TabControl,
                           Rect(TabLeft,
                                FOptions.Display.Tabs.OffsetTop,
                                TabLeft + TabWidth,
                                ClientHeight - FOptions.Display.Tabs.OffsetBottom),
                           TRUE);
      end;

      TabLeft := TabLeft + TabWidth - FOptions.Display.Tabs.TabOverlap;

      FScrollWidth := TabLeft;
    end;
  end;

  procedure SetTabPositions(var TabLeft: Integer; TabWidth, TabEndSpace: Integer; PinnedTabs: Boolean);
  var
    i, StartTabIndex, EndTabIndex: Integer;
    TabControl: TChromeTabControl;
    TabWidthAddition: Integer;
    DragTabControl: TChromeTabControl;
    CursorPos: TPoint;
    ExtraTabWidth: Integer;
    DragTabWidth, DragCursorXOffset: Integer;
  begin
    // Set the start and end tab indices
    if PinnedTabs then
    begin
      StartTabIndex := 0;
      EndTabIndex := pred(GetPinnedTabCount);
    end
    else
    begin
      StartTabIndex := GetPinnedTabCount;
      EndTabIndex := pred(Tabs.Count);
    end;

    if (FActiveDragTabObject <> nil) and
       (FActiveDragTabObject.DragTab.Pinned = PinnedTabs) then
    begin
      DragTabWidth := TabWidth + FOptions.Display.Tabs.TabOverlap;
    
      if DragTabWidth < FOptions.Display.Tabs.MinWidth then
        DragTabWidth := FOptions.Display.Tabs.MinWidth;

      DragTabControl := FDragTabControl;
    end
    else
    begin
      DragTabWidth := 0;
      DragTabControl := nil;
    end;

    if (DragTabControl <> nil) and
       (FActiveDragTabObject.SourceControl.GetControl <> Self) then
    begin
      DragCursorXOffset := FActiveDragTabObject.DragCursorOffset.X;

      if DragCursorXOffset > DragTabWidth - FOptions.Display.Tabs.TabOverlap then
        DragCursorXOffset := DragTabWidth - FOptions.Display.Tabs.TabOverlap;      

      if not SameBidiTabMode(BiDiMode, FActiveDragTabObject.SourceControl.GetBidiMode) then
        DragCursorXOffset := -DragCursorXOffset;

      CursorPos := ScreenToClient(Mouse.CursorPos);
        
      SetControlPosition(DragTabControl,
                         Rect(BidiXPos(CursorPos.X - DragCursorXOffset),
                              ControlRect.Top + FOptions.Display.Tabs.OffsetTop,
                              BidiXPos(CursorPos.X - DragCursorXOffset) + DragTabWidth,
                              ControlRect.Bottom - FOptions.Display.Tabs.OffsetBottom),
                         FALSE);
    end;

    // Step through the tabs
    for i := StartTabIndex to EndTabIndex do
    begin
      // Skip this tab if it being dragged with it's own container
      if (not FTabs[i].Visible) or
          ((FDragTabObject <> nil) and
          ((FDragTabObject.DockControl = nil) or
           (FDragTabObject.DockControl.GetControl <> Self)) and
          (i = ActiveTabIndex)) then
        Continue;

      // Find the actual tab control
      TabControl := TabControls[i];

      // Is the drag tab to the left of the current tab? If so, we need to
      // increment the position of the tabs to the right
      if (DragTabControl <> nil) and
         (DragTabControl.ControlRect.Left +
          ScrollOffset +
          (RectWidth(DragTabControl.ControlRect) div 2) +
          (FOptions.Display.Tabs.TabOverlap div 2) < TabLeft + RectWidth(DragTabControl.ControlRect)) then
      begin
        // If the Dock control is this tab set, insert the drag tab into the control
        if (ActiveDragTabObject.DockControl <> nil) and
           (ActiveDragTabObject.DockControl.GetControl = Self) then
        begin
          // Only shift the other tabs if the drag tab is visible
          TabLeft := TabLeft + RectWidth(DragTabControl.ControlRect) - FOptions.Display.Tabs.TabOverlap;
          FScrollWidth := FScrollWidth + RectWidth(DragTabControl.ControlRect) - FOptions.Display.Tabs.TabOverlap;
        end;

        // Do we need to hide the New Button?
        if ((not PinnedTabs) or (Tabs.Count = GetPinnedTabCount)) and
           (FActiveDragTabObject.DragTab.Index = pred(Tabs.Count)) then
          FActiveDragTabObject.HideAddButton := FOptions.Display.AddButton.Visibility = avRightFloating;

        // Set the index of the tab that the drag tab will move to if it is dropped now
        FActiveDragTabObject.DropTabIndex := i;

        // If the index is greater than that of the drag tab we need to decrement it
        if (FActiveDragTabObject.SourceControl.GetControl = Self) and
           (FActiveDragTabObject.DropTabIndex > FActiveDragTabObject.DragTab.Index) then
          FActiveDragTabObject.DropTabIndex := FActiveDragTabObject.DropTabIndex - 1;

        // Set the DragTabControl to nil we don't end up here again
        DragTabControl := nil;
      end;

      // Increment the horizontal tab position, but only if we're not dragging or
      // this tab is not the drag tab.
      if (not HasState(stsDragging)) or
         ((FDragTabObject <> nil) and
          (i <> FDragTabObject.DragTab.Index)) then
      begin
        // We add a sigle pixel to some of the tabs in order to align the
        // right hand side perfectly
        if (not PinnedTabs) and
           (not Tabs[i].MarkedForDeletion) and
           (TabEndSpace > 0) then
          TabWidthAddition := 1
        else
          TabWidthAddition := 0;

        if not Tabs[i].MarkedForDeletion then
        begin
          Dec(TabEndSpace);

          { TODO : Removed as the min active tab width will require more time to implement that I currently have! }
          (*if (Tabs[i].Active) and
             (TabWidth < 60) then
            ExtraTabWidth := (60 - TabWidth) div 2
          else       *)
          ExtraTabWidth := 0;

          if (HasState(stsResizing)) or
             (ExtraTabWidth <> 0) then
            SetMovementAnimation(nil);
//          else
//            SetMovementAnimation(FOptions.Animation.MovementAnimations.TabMove);

          SetControlPosition(TabControl,
                             Rect(TabLeft - ExtraTabWidth,
                                  FOptions.Display.Tabs.OffsetTop,
                                  TabLeft + TabWidth + FOptions.Display.Tabs.TabOverlap + ExtraTabWidth,
                                  ClientHeight - FOptions.Display.Tabs.OffsetBottom),
                             TRUE);

          TabLeft := TabLeft + TabWidth + TabWidthAddition;
          FScrollWidth := FScrollWidth + TabWidth + TabWidthAddition;
        end
        else
        begin
          TabLeft := TabLeft + RectWidth(TabControl.ControlRect);
          FScrollWidth := FScrollWidth + RectWidth(TabControl.ControlRect);
        end;
      end;
    end;

    // If the DragTabControl is not nil it means the drag tab is past the last tab
    if DragTabControl <> nil then
    begin
      if not DraggingInOwnContainer then
        EndTabIndex := EndTabIndex + 1;

      // If we're dragging a pinned tab, we need to leave a space at the end of the pinned tabs
      if (PinnedTabs) and (ActiveDragTabObject.DragTab.Pinned) then
      begin
        TabLeft := TabLeft + RectWidth(DragTabControl.ControlRect) - FOptions.Display.Tabs.TabOverlap;
      end
      else
        // If we're not dragging a pinned tab we need to hide the New Button
        FActiveDragTabObject.HideAddButton := FOptions.Display.AddButton.Visibility = avRightFloating;

      if Tabs.Count > 0 then
        FScrollWidth := FScrollWidth + RectWidth(TabControls[Tabs.Count - 1].ControlRect);

        // Set the Drop Tab index to the last tab
      FActiveDragTabObject.DropTabIndex := EndTabIndex;
    end;

    if FActiveDragTabObject <> nil then
    begin
      if FActiveDragTabObject.DropTabIndex < 0 then
        FActiveDragTabObject.DropTabIndex := 0;
    end;
  end;

var
  TabLeft, AddButtonLeft: Integer;
begin
  try
    FScrollWidth := 0;
    TabLeft := FTabContainerRect.Left;

    if (HasState(stsDeletingUnPinnedTabs)) and
       (HasState(stsTabDeleted)) then
    begin
      SetTabPositionsClosing(TabLeft);
    end
    else
    begin
      if not DraggingInOwnContainer then
        CalculateAverageTabWidth(FAdjustedTabWidth, FTabEndSpace);

      SetTabPositions(TabLeft, FOptions.Display.Tabs.PinnedWidth, 0, TRUE);
      SetTabPositions(TabLeft, FAdjustedTabWidth, FTabEndSpace, FALSE);
    end;

    if (FOptions.Display.AddButton.Visibility = avRightFloating) then
    begin
      if GetVisibleTabCount(TRUE) = 0 then
        AddButtonLeft := FOptions.Display.TabContainer.PaddingLeft
      else
        AddButtonLeft := TabControls[GetLastVisibleTabIndex(pred(FTabs.Count))].ControlRect.Right +
                         FOptions.Display.AddButton.Offsets.HorizontalFloating;

      if (GetTabDisplayState <> tdNormal) or (AddButtonLeft > FMaxAddButtonRight) then
        AddButtonLeft := FMaxAddButtonRight;

      SetControlPosition(FAddButtonControl,
                         Rect(AddButtonLeft,
                              FOptions.Display.AddButton.Offsets.Vertical,
                              AddButtonLeft +FOptions.Display.AddButton.Width,
                              FOptions.Display.AddButton.Height + FOptions.Display.AddButton.Offsets.Vertical),
                         FALSE);
    end;

    if FScrollWidth <> FPreviousScrollWidth then
      DoOnScrollWidthChanged;

    FPreviousScrollWidth := FScrollWidth;

    // Calculate the position of the next control
    if Tabs.Count = 0 then
      TabLeft := 0
    else
      TabLeft := TabControls[Tabs.Count - 1].ControlRect.Right;

    TabLeft := FScrollWidth + FOptions.Display.Tabs.TabOverlap + FOptions.Display.AddButton.Offsets.Horizontal + FOptions.Display.Tabs.OffsetLeft;
  finally
    // Reset the drag status now we're drawn everything
    if (HasState(stsCancellingDrag)) or
       (HasState(stsCompletingDrag)) then
    begin
      // Finish the drag sequence
      RemoveState(stsCancellingDrag);
      RemoveState(stsCompletingDrag);
    end;

    RemoveState(stsResizing);
  end;
end;

function TCustomChromeTabs.GetOptions: TOptions;
begin
  Result := FOptions;
end;

function TCustomChromeTabs.GetImagesOverlay: TCustomImageList;
begin
  Result := FImagesOverlay;
end;

procedure TCustomChromeTabs.PaintWindow(DC: HDC);
begin
  Canvas.Lock;
  try
    Canvas.Handle := DC;
    try
      DrawCanvas;
    finally
      Canvas.Handle := 0;
    end;
  finally
    Canvas.Unlock;
  end;
end;

function TCustomChromeTabs.CorrectedClientWidth: Integer;
begin
  Result := Width;
end;

procedure TCustomChromeTabs.CorrectScrollOffset(AlwaysCorrect: Boolean);
var
  LastTabIndex: Integer;
begin
  if (FOptions.Scrolling.Enabled) and
     (ScrollOffset > 0) and
     ((AlwaysCorrect) or
      (FLastClientWidth < CorrectedClientWidth)) then
  begin
    // Make sure we're showing as many tabs as possible
    LastTabIndex := GetLastVisibleTabIndex(Tabs.Count - 1);

    if LastTabIndex <> -1 then
    begin
      if TabControls[LastTabIndex].ControlRect.Right < ScrollOffset + ClientWidth then
        ScrollOffset := GetMaxScrollOffset;
    end;
  end;

  FLastClientWidth := CorrectedClientWidth;
end;

procedure TCustomChromeTabs.Resize;
begin
  inherited;

  if FOptions <> nil then
  begin
    CorrectScrollOffset;

    AddState(stsResizing);

    SetControlDrawStates(TRUE);

    InvalidateAllControls;

    Redraw;
  end;
end;

procedure TCustomChromeTabs.InvalidateAllControls;
var
  i: Integer;
begin
  if (not HasState(stsLoading)) and
     (not FInvalidatingControls) then
  begin
    FInvalidatingControls := TRUE;
    try
      for i := 0 to pred(Tabs.Count) do
        SetControlDrawState(TabControls[i], TabControls[i].DrawState, TRUE);

      FLookAndFeel.Invalidate;
      FScrollButtonLeftControl.Invalidate;
      FScrollButtonRightControl.Invalidate;
      FAddButtonControl.Invalidate;

      AddState(stsControlPositionsInvalidated);

      Redraw;
    finally
      FInvalidatingControls := FALSE;
    end;
  end;
end;

function TCustomChromeTabs.IsDragging: Boolean;
begin
  Result := FActiveDragTabObject <> nil;
end;

function TCustomChromeTabs.IsValidTabIndex(Index: Integer): Boolean;
begin
  Result := (Index >= -1) and (Index < FTabs.Count);
end;

procedure TCustomChromeTabs.Loaded;
begin
  inherited;

  UpdateTabControlProperties;

  EndUpdate; // BeginUpdate called in Create

  // No Longer loading, so we can start drawing
  RemoveState(stsLoading);

  // Set the intial scroll position
  ScrollOffset := 0;

  // Fix the draw states
  FAddButtonControl.SetDrawState(dsNotActive, 0, ttNone, TRUE);
  FScrollButtonLeftControl.SetDrawState(dsNotActive, 0, ttNone, TRUE);
  FScrollButtonRightControl.SetDrawState(dsNotActive, 0, ttNone, TRUE);

  // Make sure we reset all the control positions
  AddState(stsControlPositionsInvalidated);

  SetControlDrawStates(TRUE);
  
  AddState(stsFirstPaint);
  
  // Force a redraw
  Redraw;
end;

procedure TCustomChromeTabs.LoadLookAndFeel(Stream: TStream);
var
  TabsLookAndFeel: TTabsLookAndFeel;
begin
  BeginUpdate;
  try
    TabsLookAndFeel := TTabsLookAndFeel.Create(nil);
    try
      TabsLookAndFeel.LookAndFeel := FLookAndFeel;

      ReadComponentFromStream(TabsLookAndFeel, Stream);
    finally
      FreeAndNil(TabsLookAndFeel);
    end;
  finally
    EndUpdate;
  end;
end;

procedure TCustomChromeTabs.LoadLookAndFeel(const Filename: String);
var
  FileStream: TFileStream;
begin
  FileStream := TFileStream.Create(Filename, fmOpenRead);
  try
    LoadLookAndFeel(FileStream);
  finally
    FreeAndNil(FileStream);
  end;
end;

procedure TCustomChromeTabs.LoadOptions(const Filename: String);
var
  FileStream: TFileStream;
begin
  FileStream := TFileStream.Create(Filename, fmOpenRead);
  try
    LoadOptions(FileStream);
  finally
    FreeAndNil(FileStream);
  end;
end;

function TCustomChromeTabs.LookAndFeelToCode: String;
var
  TabsLookAndFeel: TTabsLookAndFeel;
begin
  TabsLookAndFeel := TTabsLookAndFeel.Create(nil);
  try
    TabsLookAndFeel.LookAndFeel := FLookAndFeel;

    Result := ComponentToCode(TabsLookAndFeel, DefaultCodeComponentName);
  finally
    FreeAndNil(TabsLookAndFeel);
  end;
end;

procedure TCustomChromeTabs.LoadOptions(Stream: TStream);
var
  TabsOptions: TTabsOptions;
begin
  BeginUpdate;
  try
    TabsOptions := TTabsOptions.Create(nil);
    try
      TabsOptions.Options := FOptions;

      ReadComponentFromStream(TabsOptions, Stream);
    finally
      FreeAndNil(TabsOptions);
    end;
  finally
    EndUpdate;
  end;
end;

procedure TCustomChromeTabs.UpdateTabControlProperties;
var
  i: Integer;
begin
  for i := 0 to pred(FTabs.Count) do
    SetControlDrawState(TabControls[i], TabControls[i].DrawState, TRUE);
end;

procedure TCustomChromeTabs.SetActiveTab(const Value: TChromeTab);
begin
  if Value <> nil then
    FTabs.ActiveTab := Value;
end;

procedure TCustomChromeTabs.SetActiveTabIndex(const Value: Integer);
begin
  if Value = -1 then
    Tabs.ActiveTab := nil
  else
  if IsValidTabIndex(Value) then
    Tabs.ActiveTab := FTabs[Value];
end;

procedure TCustomChromeTabs.SetBiDiMode(Value: TBiDiMode);
begin
  inherited;

  Redraw;
end;

procedure TCustomChromeTabs.SetLookAndFeel(Value: TChromeTabsLookAndFeel);
begin
  FLookAndFeel.Assign(Value);
end;

function TCustomChromeTabs.GetLookAndFeel: TChromeTabsLookAndFeel;
begin
  Result := FLookAndFeel;
end;

procedure TCustomChromeTabs.SetTabs(const Value: TChromeTabsList);
begin
  FTabs.Assign(Value);
end;

procedure TCustomChromeTabs.TabDragDrop(Sender: TObject; X, Y: Integer; DragTabObject: IDragTabObject; Cancelled: Boolean; var TabDropOptions: TTabDropOptions);
begin
  // Process the drop event
  AddState(stsControlPositionsInvalidated);

  // Reset the position of the drag tab
  if FDragTabControl <> nil then
    SetControlLeft(FDragTabControl, FDragTabControl.ControlRect.Left + ScrollOffset, FALSE);

  DoOnTabDragDrop(X, Y, DragTabObject, Cancelled, TabDropOptions);
end;

procedure TCustomChromeTabs.TabDragOver(Sender: TObject; X, Y: Integer;
  State: TDragState; DragTabObject: IDragTabObject; var Accept: Boolean);
begin
  Accept := DragTabInTabRect(X, Y);

  DoOnTabDragOver(X, Y, State, DragTabObject, Accept);

  AddState(stsControlPositionsInvalidated);

  if (Accept) or (State = dsDragLeave) then
  begin
    FActiveDragTabObject := DragTabObject;

    // Do we need to scroll the container?
    if (State <> dsDragLeave) and
       (FOptions.Scrolling.Enabled) and
       (FOptions.Scrolling.DragScroll) then
    begin
      if (X <= BidiRect(FTabContainerRect).Right) and
         (X >= BidiRect(FTabContainerRect).Right - FOptions.Scrolling.DragScrollOffset) then
      begin
        ScrollTabs(mdsRight);
      end else

      if (X >= BidiRect(FTabContainerRect).Left) and
         (X <= BidiRect(FTabContainerRect).Left + FOptions.Scrolling.DragScrollOffset) then
      begin
        ScrollTabs(mdsLeft);
      end
      else
        FScrollTimer.Enabled := FALSE;
    end;

    case State of
      dsDragEnter:
        begin
          // If it's this control initiating the drag, just use the
          // active tab as the drag control
          if DragTabObject.SourceControl.GetControl = Self then
            FDragTabControl := TabControls[ActiveTabIndex] else

          // Otherwise, we need to create a temporary tab control
          if FDragTabControl = nil then
          begin
            FDragTabControl := TChromeTabControl.Create(Self, DragTabObject.DragTab);

            SetControlDrawState(FDragTabControl, dsActive, FALSE);

            if ActiveTabIndex <> -1 then
              SetControlDrawState(TabControls[ActiveTabIndex], dsNotActive, TRUE);
          end;

          FDragTabControl.ScrollableControl := FALSE;
        end;

      dsDragLeave:
        begin
          // Free the dragtabcontrol if required
          if FDragTabControl <> nil then
            FDragTabControl.ScrollableControl := TRUE;

          FScrollTimer.Enabled := FALSE;

          if DragTabObject.SourceControl.GetControl = Self then
          begin
            FDragTabControl := nil;
          end
          else
          begin
            if (ActiveTabIndex >= 0) and (ActiveTabIndex < Tabs.Count) then
              SetControlDrawState(TabControls[ActiveTabIndex], dsActive, TRUE);

            // Free the temporary drag tab control
            FreeAndNil(FDragTabControl);
          end;

          if FActiveDragTabObject.SourceControl = FActiveDragTabObject.DockControl then
            FActiveDragTabObject.HideAddButton := TRUE;

          // Clear the drag object reference
          FActiveDragTabObject := nil;

          AddState(stsControlPositionsInvalidated);
          
          Redraw;
        end;

      dsDragMove:
        begin
          Redraw;
        end;
    end;
  end;
end;

procedure TCustomChromeTabs.ShowTabDragForm(X, Y: Integer; FormVisible: Boolean);
var
  DragFormPoint: TPoint;
begin
  DragFormPoint := ClientToScreen(Point(X, Y));

  if (FDragTabObject.DragForm = nil) and (FormVisible) then
    FDragTabObject.DragForm := CreateDragForm(FTabs[FDragTabObject.DragTab.Index]);

  if FDragTabObject.DragForm <> nil then
  begin
    // Set the position
    FDragTabObject.DragForm.Left := DragFormPoint.X - FDragTabObject.DragFormOffset.X;
    FDragTabObject.DragForm.Top := DragFormPoint.Y - FDragTabObject.DragFormOffset.Y;

    FDragTabObject.DragForm.Visible := FormVisible;
  end;
end;

procedure TCustomChromeTabs.Redraw;
begin
  if FUpdateCount = 0 then
  begin
    RemoveState(stsPendingUpdates);

    Repaint;
  end
  else
  begin
    Inc(FPausedUpdateCount);

    AddState(stsPendingUpdates);
  end;
end;

procedure TCustomChromeTabs.WMContextMenu(var Message: TWMContextMenu);
var
  ScreenPoint: TPoint;
begin
  ScreenPoint := ClientToScreen(Point(FLastMouseX, FLastMouseY));

  if Assigned(PopupMenu) then
  begin
    PopupMenu.Popup(ScreenPoint.X, ScreenPoint.Y);
  end
  else
  begin
    if FOptions.Behaviour.UseBuiltInPopupMenu then
      DoPopup(Self, ScreenPoint);
  end;
end;

procedure TCustomChromeTabs.WMERASEBKGND(var Message: TWMEraseBkgnd);
begin
  Message.Result := 1;
end;

procedure TCustomChromeTabs.WMPaint(var Message: TWMPaint);
begin
  PaintHandler(Message);
end;

procedure TCustomChromeTabs.WMWindowPosChanged(var Message: TWMWindowPosChanged);
begin
  inherited;
  if not(csLoading in ComponentState) then
    Redraw;
end;

procedure TCustomChromeTabs.WndProc(var Message: TMessage);
begin
  if (FDragTabObject <> nil) and
     (Message.Msg = CN_KEYDOWN) and
     (Message.WParam = VK_ESCAPE) then
  begin
    FDragCancelled := TRUE;

    SendMessage(Handle, WM_LBUTTONUP, 0, 0);
  end;

  inherited;
end;

procedure TCustomChromeTabs.DragCompleted;
begin
  AddState(stsControlPositionsInvalidated);

  Redraw;
end;

function TCustomChromeTabs.DraggingDockedTab: Boolean;
begin
  Result := (ActiveDragTabObject <> nil) and
            (ActiveDragTabObject.DockControl <> nil) and
            (ActiveDragTabObject.DockControl.GetControl = Self);
end;

function TCustomChromeTabs.DraggingInOwnContainer: Boolean;
begin
  Result := (FDragTabObject <> nil) and
            ((FDragTabObject.DockControl <> nil) and
             (FDragTabObject.DockControl.GetControl = Self));
end;

function TCustomChromeTabs.ActiveTabVisible: Boolean;
begin
  Result := (FDragTabObject = nil) or
            ((FDragTabObject.DockControl <> nil) and
             ((FDragTabObject.SourceControl = nil) or
              (FDragTabObject.SourceControl.GetControl = Self)));

  // Split for clarity
  if Result then
  begin
    if (FDragTabObject <> nil) and
       (FDragTabObject.SourceControl <> nil) and
       (FDragTabObject.SourceControl.GetControl = Self) and
       ((FDragTabObject.DockControl = nil) or
        (FDragTabObject.DockControl.GetControl <> Self)) then
      Result := FALSE;
  end;
end;

procedure TCustomChromeTabs.DrawCanvas;
var
  TabCanvas, BackgroundCanvas: TGPGraphics;

  procedure SetTabClipRegion;
  begin
    TabCanvas.ResetClip;

    // Set the clip region while re're drawing the tabs if we're not
    // overlaying the buttons
    if FOptions.Display.TabContainer.OverlayButtons then
      TabCanvas.SetClip(RectToGPRectF(BidiRect(Rect(FOptions.Display.Tabs.OffsetLeft,
                                               FOptions.Display.Tabs.OffsetTop,
                                               CorrectedClientWidth - FOptions.Display.Tabs.OffsetRight,
                                               ClientHeight - FOptions.Display.Tabs.OffsetBottom))))
    else
      TabCanvas.SetClip(RectToGPRectF(BidiRect(TabContainerRect)));
  end;

var
  i: Integer;
  Handled: Boolean;
  Targets: Array of TGPGraphics;
  DrawTicks: Cardinal;
  Pen: TGPPen;
  PrevVisibleIndex: Integer;
  ClipPolygons: IChromeTabPolygons;
begin
  // Don't draw while we're loading
  if (not HasState(stsLoading)) and
     ((csDesigning in ComponentState) or
      (Visible)) then
  try
    DrawTicks := GetTickCount;
    try
      if (HasState(stsControlPositionsInvalidated)) or
         ((HasState(stsAnimatingMovement)) and (GetTabDisplayState = tdNormal)) then
      begin
        RemoveState(stsControlPositionsInvalidated);

        CalculateRects;

        // Recalculate the size of the controls
        RepositionTabs;
      end;

      if HasState(stsFirstPaint) then
      begin
        // Remove the first paint state as this should only be done once
        RemoveState(stsFirstPaint);

        // Update the control states before the first paint, but after the
        // control positions have been calculated
        SetControlDrawStates(TRUE);
      end;

      // Set the canvas size
      FCanvasBmp.Width := ClientWidth;
      FCanvasBmp.Height := ClientHeight;

      FBackgroundBmp.Width := ClientWidth;
      FBackgroundBmp.Height := ClientHeight;

      TabCanvas := TGPGraphics.Create(FCanvasBmp.Canvas.Handle);
      BackgroundCanvas := TGPGraphics.Create(FBackgroundBmp.Canvas.Handle);
      try
        // Set the canvas properties
        TabCanvas.SetSmoothingMode(FOptions.Display.Tabs.CanvasSmoothingMode);
        BackgroundCanvas.SetSmoothingMode(FOptions.Display.Tabs.CanvasSmoothingMode);

        // Allow the user to draw the tab canvas
        DoOnBeforeDrawItem(TabCanvas, ControlRect, itTabContainer, -1, Handled);

        // If it hasn't been handled, draw it now
        if not Handled then
        begin
          SetLength(Targets, 1);

          Targets[0] := TabCanvas;
        end;

        // Allow the user to draw the tab canvas
        DoOnBeforeDrawItem(BackgroundCanvas, ControlRect, itBackground, -1, Handled);

        // If it hasn't been handled, draw it now
        if not Handled then
        begin
          SetLength(Targets, length(Targets) + 1);

          Targets[high(Targets)] := BackgroundCanvas;
        end;

        // If it hasn't been handled, draw it now
        DrawBackGroundTo(Targets);

        // After background draw event
        DoOnAfterDrawItem(BackgroundCanvas, ControlRect, itBackground, -1);

        // Draw the inactive tabs
        for i := pred(FTabs.Count) downto 0 do
        begin
          if (Tabs[i].Visible) and
             (i <> ActiveTabIndex) and
             (TabControls[i].ControlRect.Right >= ScrollOffset) and
             (TabControls[i].ControlRect.Left <= CorrectedClientWidth + ScrollOffset) then
          begin
            SetTabClipRegion;

            ClipPolygons := nil;

            // Save the current clip region of the GPGraphics
            if (not FOptions.Display.Tabs.SeeThroughTabs) and
               ((FDragTabObject = nil) or (ActiveTabIndex <> i)) then
            begin
              ClipPolygons := TChromeTabPolygons.Create;

              // Find the index of the previous visible tab
              PrevVisibleIndex := GetLastVisibleTabIndex(i - 1);

              // Excluse the clip region of the previous tab as long as we're not dragging in this container
              if (PrevVisibleIndex <> -1) and
                 ((FDragTabObject = nil) or (PrevVisibleIndex <> ActiveTabIndex)) then
                ClipPolygons.AddPolygon(TabControls[PrevVisibleIndex].GetPolygons.Polygons[0].Polygon, nil, nil);

              // Exclude the clip region of the next tab
              if (ActiveTab <> nil) and
                 (i + 1 = ActiveTabIndex) and
                 (FDragTabObject = nil) then
                ClipPolygons.AddPolygon(TabControls[ActiveTabIndex].GetPolygons.Polygons[0].Polygon, nil, nil);
            end;

            // Draw the tab
            TabControls[i].DrawTo(TabCanvas, FLastMouseX, FLastMouseY, ClipPolygons);
          end;
        end;

        // Clear the clipping region while we draw the base line
        if FOptions.Display.Tabs.BaseLineTabRegionOnly then
          SetTabClipRegion
        else
          TabCanvas.ResetClip;

        // Draw the bottom line
        Pen :=  FLookAndFeel.Tabs.BaseLine.GetPen;

        case FOptions.Display.Tabs.Orientation of
          toTop: TabCanvas.DrawLine(Pen, 0, TabContainerRect.Bottom - 1, CorrectedClientWidth, TabContainerRect.Bottom - 1);
          toBottom: TabCanvas.DrawLine(Pen, 0, TabContainerRect.Top, CorrectedClientWidth, TabContainerRect.Top);
        end;

        // Restore the tab clip region
        SetTabClipRegion;

        // Draw the active tab
        if (ActiveTabIndex <> -1) and
           (ActiveTabVisible) and
           (TabControls[ActiveTabIndex].ControlRect.Right >= ScrollOffset) and
           (TabControls[ActiveTabIndex].ControlRect.Left <= CorrectedClientWidth + ScrollOffset) then
          TabControls[ActiveTabIndex].DrawTo(TabCanvas, FLastMouseX, FLastMouseY);

        // Clear the clip region
        TabCanvas.ResetClip;

        // Draw the drag tab if required
        if FDragTabControl <> nil then
          FDragTabControl.DrawTo(TabCanvas, FLastMouseX, FLastMouseY);

        // Draw the new button
        if (FOptions.Display.AddButton.Visibility <> avNone) and
           ((not DraggingDockedTab) or
            (not FActiveDragTabObject.HideAddButton)) and
           ((FDragTabObject = nil) or (not FDragTabObject.HideAddButton)) and
           (RectWidth(FAddButtonControl.ControlRect) <= ClientWidth) then
          FAddButtonControl.DrawTo(TabCanvas, FLastMouseX, FLastMouseY);

        // Draw the left and right scroll buttons
        if FOptions.Scrolling.Enabled then
        begin
          if ScrollButtonLeftVisible then
            FScrollButtonLeftControl.DrawTo(TabCanvas, FLastMouseX, FLastMouseY);

          if ScrollButtonRightVisible then
            FScrollButtonRightControl.DrawTo(TabCanvas, FLastMouseX, FLastMouseY);
        end;

        // After control draw event
        DoOnAfterDrawItem(TabCanvas, ControlRect, itTabContainer, -1);
      finally
        FreeAndNil(TabCanvas);
        FreeAndNil(BackgroundCanvas);
      end;
    finally
      DoOnDebugLog('Canvas Draw: %d ms', [GetTickCount - DrawTicks]);
    end;

    // Draw the canvas bitmap to the control canvas
    BitBlt(Canvas.Handle, 0, 0, FCanvasBmp.Width, FCanvasBmp.Height, FCanvasBmp.Canvas.Handle, 0, 0, SRCCOPY);
  finally
    RemoveState(stsEndTabDeleted);
  end;
end;

function TCustomChromeTabs.ControlRect: TRect;
begin
  Result := Rect(0, 0, ClientWidth, ClientHeight);
end;

function TCustomChromeTabs.ScrollRect(ARect: TRect): TRect;
begin
  Result := Rect(ARect.Left - BidiScrollOffset,
                 ARect.Top,
                 ARect.Right - BidiScrollOffset,
                 ARect.Bottom);
end;

procedure TCustomChromeTabs.ScrollIntoView(Tab: TChromeTab);
begin
  if TabControls[Tab.Index].EndRect.Left < ScrollOffset then
    ScrollOffset := TabControls[Tab.Index].EndRect.Left else

  if TabControls[Tab.Index].EndRect.Right > TabContainerRect.Right + ScrollOffset then
    ScrollOffset := TabControls[Tab.Index].EndRect.Right - RectWidth(TabContainerRect) + FOptions.Display.Tabs.TabOverlap;
end;

function TCustomChromeTabs.ScrollRect(ALeft, ATop, ARight, ABottom: Integer): TRect;
begin
  Result := Rect(ALeft - ScrollOffset,
                 ATop,
                 ARight - ScrollOffset,
                 ABottom);
end;

procedure TCustomChromeTabs.DrawBackGroundTo(Targets: Array of TGPGraphics);
var
  GPImage: TGPImage;
  i: Integer;
  MemStream: TMemoryStream;
begin
  PaintControlToCanvas(Self, FCanvasBmp.Canvas);
  PaintControlToCanvas(Self, FBackgroundBmp.Canvas);

  MemStream := TMemoryStream.Create;
  try
    FCanvasBmp.SaveToStream(MemStream);

    MemStream.Position := 0;

    GPImage := TGPImage.Create(TStreamAdapter.Create(MemStream));
    try
      for i := low(Targets) to high(Targets) do
      begin
        // Draw the background if required
        if not FOptions.Display.TabContainer.TransparentBackground then
        begin
          Targets[i].FillRectangle(FLookAndFeel.TabsContainer.GetBrush(ControlRect), RectToGPRectF(ControlRect));
          Targets[i].DrawRectangle(FLookAndFeel.TabsContainer.GetPen, RectToGPRectF(ControlRect));
        end;
      end;
    finally
      FreeAndNil(GPImage);
    end;
  finally
    FreeAndNil(MemStream);
  end;
end;

{ TWindowFromPointFixThread }

constructor TWindowFromPointFixThread.Create(Pt: TPoint; Range, Step: Integer);
begin
  inherited Create(FALSE);

  FPoint := Pt;
  FRange := Range;
  FStep := Step;
end;

function FindChromeTabsControlAt(X, Y: Integer; var ChromeTabs: TCustomChromeTabs): Boolean;
var
  H: THandle;
  WinControl: TWinControl;
begin
  H:= WindowFromPoint(Point(X, Y));

  WinControl := FindControl(H);

  Result := WinControl is TCustomChromeTabs;

  if Result then
    ChromeTabs := TCustomChromeTabs(WinControl)
  else
    ChromeTabs := nil;
end;

procedure TWindowFromPointFixThread.Execute;
var
  i: Integer;
  ChromeTabs: TCustomChromeTabs;
begin
  i := FRange;

  while i >= 0 do
  begin
    if i = 0 then
      FindChromeTabsControlAt(FPoint.X, FPoint.Y, ChromeTabs)
    else
    begin
      if (FindChromeTabsControlAt(FPoint.X - i, FPoint.Y - i, ChromeTabs)) or
         (FindChromeTabsControlAt(FPoint.X + i, FPoint.Y - i, ChromeTabs)) or
         (FindChromeTabsControlAt(FPoint.X + i, FPoint.Y + i, ChromeTabs)) or
         (FindChromeTabsControlAt(FPoint.X - i, FPoint.Y + i, ChromeTabs)) then
        Break;
    end;

    i := i - FStep;
  end;

  ReturnValue := Integer(ChromeTabs);
end;

end.
