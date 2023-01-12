/**
  Copyright (C) 2012-2021 by Autodesk, Inc.
  All rights reserved.

  DATRON post processor configuration.

  $Revision$
  $Date$

  FORKID {DC597035-3395-48C2-BA86-28EFF6A7E339}
*/

description = "DATRON C5";
vendor = "DATRON";
vendorUrl = "http://www.datron.com";
legal = "Copyright (C) 2012-2021 by Autodesk, Inc.";
certificationLevel = 2;
minimumRevision = 45702;

longDescription = "Post for DATRON C5.";

extension = "mcr";
setCodePage("ascii");

capabilities = CAPABILITY_MILLING;
tolerance = spatial(0.002, MM);

minimumChordLength = spatial(0.25, MM);
minimumCircularRadius = spatial(0.01, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.01);
maximumCircularSweep = toRad(90);
allowHelicalMoves = false;
allowedCircularPlanes = (1 << PLANE_XY); // allow XY plane only
mapWorkOrigin = false;

// user-defined properties
properties = {
  writeMachine: {
    title      : "Write machine",
    description: "Output the machine settings in the header of the code.",
    group      : "formats",
    type       : "boolean",
    value      : true,
    scope      : "post"
  },
  writeVersion: {
    title      : "Write version",
    description: "Write the version number in the header of the code.",
    group      : "formats",
    type       : "boolean",
    value      : false,
    scope      : "post"
  },
  showOperationDialog: {
    title      : "Show operation dialog",
    description: "Shows a start dialog on the control which allows you to select the operation to start with.",
    group      : "preferences",
    type       : "boolean",
    value      : true,
    scope      : "post"
  },
  useParametricFeed: {
    title      : "Parametric feed",
    description: "Specifies the feed value that should be output using a Q value.",
    group      : "preferences",
    type       : "boolean",
    value      : true,
    scope      : "post"
  },
  showNotes: {
    title      : "Show notes",
    description: "Writes operation notes as comments in the outputted code.",
    group      : "formats",
    type       : "boolean",
    value      : false,
    scope      : "post"
  },
  useSmoothing: {
    title      : "Use smoothing",
    description: "Specifies if smoothing should be used or not.",
    group      : "preferences",
    type       : "boolean",
    value      : true,
    scope      : "post"
  },
  useDynamic: {
    title      : "Dynamic mode",
    description: "Specifies the using of dynamic mode or not.",
    group      : "preferences",
    type       : "boolean",
    value      : true,
    scope      : "post"
  },
  useTimeStamp: {
    title      : "Time stamp",
    description: "Specifies whether to output a time stamp.",
    group      : "preferences",
    type       : "boolean",
    value      : false,
    scope      : "post"
  },
  useCoolant: {
    title      : "Write coolant commands",
    description: "Enable/disable coolant code outputs for the entire program.",
    group      : "preferences",
    type       : "boolean",
    value      : false,
    scope      : "post"
  }
};

// samples:
// {id: COOLANT_THROUGH_TOOL, on: 88, off: 89}
// {id: COOLANT_THROUGH_TOOL, on: [8, 88], off: [9, 89]}
var coolants = [
  {id:COOLANT_FLOOD, on:1},
  {id:COOLANT_MIST, on:1},
  {id:COOLANT_THROUGH_TOOL},
  {id:COOLANT_AIR, on:3},
  {id:COOLANT_AIR_THROUGH_TOOL},
  {id:COOLANT_SUCTION},
  {id:COOLANT_FLOOD_MIST},
  {id:COOLANT_FLOOD_THROUGH_TOOL},
  {id:COOLANT_OFF, off:2}
];

var mFormat = createFormat({prefix:"M", width:2, zeropad:true, decimals:1});

var xyzFormat = createFormat({decimals:(unit == MM ? 5 : 5), forceDecimal:false});
var angleFormat = createFormat({decimals:5, scale:DEG});
var abcFormat = createFormat({decimals:5, scale:DEG});
var feedFormat = createFormat({decimals:(unit == MM ? 2 : 2), scale:(unit == MM ? 0.001 : 1)});
var toolFormat = createFormat({decimals:0});
var rpmFormat = createFormat({decimals:0, scale:0.001});
var secFormat = createFormat({decimals:3, forceDecimal:true}); // seconds - range 0.001-99999.999
var milliFormat = createFormat({decimals:0}); // milliseconds // range 1-9999
var workpieceFormat = createFormat({decimals:(unit == MM ? 3 : 4), forceSign:true, width:7, trim:false});

var xOutput = createVariable({force:true}, xyzFormat);
var yOutput = createVariable({force:true}, xyzFormat);
var zOutput = createVariable({onchange:function () {retracted = false;}, force:true}, xyzFormat);
var aOutput = createVariable({force:true}, abcFormat);
var bOutput = createVariable({force:true}, abcFormat);
var cOutput = createVariable({force:true}, abcFormat);
var feedOutput = createVariable({}, feedFormat);
var sOutput = createVariable({prefix:"S", force:true}, rpmFormat);

var gMotionModal = createModal({prefix:"Axyz ", force:true, suffix:","}, xyzFormat); // modal group 1 // G0-G3, ...

// fixed settings
var language = "en"; // supported languages are: "en", "de"
var allowIndexingWCSProbing = false; // specifies that probe WCS with tool orientation is supported

// collected state
var currentWorkOffset;
var currentFeedValue = -1;
var optionalSection = false;
var forceSpindleSpeed = false;
var activeMovements; // do not use by default
var currentFeedId;
var containsProbingOperations = false;
var retracted = false; // specifies that the tool has been retracted to the safe plane

// format date + time
var timeFormat = createFormat({decimals:0, width:2, zeropad:true});
var now = new Date();
var nowDay = now.getDate();
var nowMonth = now.getMonth() + 1;
var nowHour = now.getHours();
var nowMin = now.getMinutes();
var nowSec = now.getSeconds();

/**
  Writes the specified block.
*/
function writeBlock() {
  writeWords(arguments);
}

var charMap = {
  "\u00c4": "Ae",
  "\u00e4": "ae",
  "\u00dc": "Ue",
  "\u00fc": "ue",
  "\u00d6": "Oe",
  "\u00f6": "oe",
  "\u00df": "ss",
  "\u002d": "_"
};

/** Map specific chars. */
function mapComment(text) {
  var result = "";
  for (var i = 0; i < text.length; ++i) {
    var ch = charMap[text[i]];
    result += ch ? ch : text[i];
  }
  return result;
}

function formatComment(text) {
  return mapComment(text);
}

function formatVariable(text) {
  var mapped = mapComment(text.substring(0, 1).toUpperCase() + text.substring(1).toLowerCase());
  return mapped.replace(/[^A-Za-z0-9\-_]/g, "");
}

/**
  Output a comment.
*/
function writeComment(text) {
  writeln("; !" + formatComment(text) + "!");
}

function onOpen() {

  if (true) { // note: setup your machine here
    var aAxis = createAxis({coordinate:0, table:true, axis:[1, 0, 0], range:[0, 100.001], preference:0});
    var cAxis = createAxis({coordinate:2, table:true, axis:[0, 0, 1], range:[0, 360], cyclic:true, preference:0});
    machineConfiguration = new MachineConfiguration(aAxis, cAxis);

    setMachineConfiguration(machineConfiguration);
    optimizeMachineAngles2(0); // TCP mode
  }

  if (!machineConfiguration.isMachineCoordinate(0)) {
    aOutput.disable();
  }
  if (!machineConfiguration.isMachineCoordinate(1)) {
    bOutput.disable();
  }
  if (!machineConfiguration.isMachineCoordinate(2)) {
    cOutput.disable();
  }

  var numberOfSections = getNumberOfSections();
  for (var i = 0; i < numberOfSections; ++i) {
    var section = getSection(i);
    if (isProbeOperation(section)) {
      containsProbingOperations = true;
      break;
    }
  }

  // header
  writeProgramHeader();
}

function getOperationDescription(section) {
  var operationComment = "";
  if (section.hasParameter("operation-comment")) {
    operationComment = section.getParameter("operation-comment");
    operationComment = formatComment(operationComment);
  }

  var cycleTypeString = "";
  if (section.hasParameter("operation:cycleType")) {
    cycleTypeString = localize(section.getParameter("operation:cycleType")).toString();
    cycleTypeString = formatComment(cycleTypeString);
  }

  var sectionID = section.getId() + 1;
  var description = operationComment/* + "_" + cycleTypeString + "_" + sectionID*/;
  return description;
}

/** Writes the tool table. */
function writeToolTable() {
  var tools = getToolTable();
  writeBlock("; !" + translate("Number of tools in use") + ": " + tools.getNumberOfTools() + "!");
  if (tools.getNumberOfTools() > 0) {
    for (var i = 0; i < tools.getNumberOfTools(); ++i) {
      var tool = tools.getTool(i);
      var comment = "T" + (tool.number) + " = " + toolFormat.format(tool.number) + ";!" +
      formatComment(getToolTypeName(tool.type)) + " " +
      "D:" + xyzFormat.format(tool.diameter) + " " +
      "L2:" + xyzFormat.format(tool.fluteLength) + " " +
      "L3:" + xyzFormat.format(tool.shoulderLength) + "!";
      writeBlock(comment);
    }
  }
}

/** Writes the program header. */
function writeProgramHeader() {
  var date =  timeFormat.format(nowDay) + "." + timeFormat.format(nowMonth) + "." + now.getFullYear();
  var time = timeFormat.format(nowHour) + ":" + timeFormat.format(nowMin);

  if (getProperty("useTimeStamp")) {
    writeBlock("!Makro file ; generated at " + date + " - " + time + " V9.85D!");
  } else {
    writeBlock("!Makro file ; V9.85D!");
  }
  if (programComment) {
    writeBlock("!" + formatComment(programComment) + "!");
  } else {
    writeBlock("!Makroprojekt description!");
  }
  writeln("");

  writeln("!Please make sure that the language on your control is set to " + "\"" + language + "\"" + "!");
  switch (language) {
  case "en":
    writeBlock("_sprache 1;");
    break;
  case "de":
    writeBlock("_sprache 0;");
    break;
  default:
    writeBlock("_sprache 1;");
  }

  writeln("");
  switch (unit) {
  case IN:
    writeBlock("Dimension 2;");
    break;
  case MM:
    writeBlock("Dimension 1;");
    break;
  }

  writeln("");

  var variablesDeclaration = new Array();
  var submacrosDeclaration = new Array();
  var dialogsDeclaration = new Array();

  if (getProperty("showOperationDialog")) {
    variablesDeclaration.push("optional_stop");
  }
  variablesDeclaration.push("$Message");

  dialogsDeclaration.push("_maske _haupt, " + "1000" + ", 0, " + "\"" + translate("Submacro") + " " + translate("Description") + "\"");
  if (getProperty("showOperationDialog")) {
    dialogsDeclaration.push("_feld optional_stop, 1, 0, 0, 0, 1, 2, 0," + " \"" + "optional_stop" + "\"" + "," + " \"" + "optional_stop" + "\"");
  }

  // Write variables declaration
  var tools = getToolTable();
  for (var i = 0; i < tools.getNumberOfTools(); ++i) {
    var tool = tools.getTool(i);
    variablesDeclaration.push("T" + tool.number);
  }

  var numberOfSections = getNumberOfSections();
  if (getProperty("showOperationDialog")) {
    var dropDownElements = new Array();
    variablesDeclaration.push("startOperation");
  }

  var dropDownDialog = "_feld startOperation, 1, 0, 1, 0, 9999, 1, 0, \"Startoperation <";

  for (var i = 0; i < numberOfSections; ++i) {
    var section = getSection(i);
    var sectionID = i + 1;
    variablesDeclaration.push("Op_" + formatVariable(getOperationDescription(section)));
    submacrosDeclaration.push("Sm_" + formatVariable(getOperationDescription(section)));
    if (getProperty("showOperationDialog")) {
      dropDownElements.push(formatVariable(getOperationDescription(section)) + "<" + sectionID + ">");
    }
    if (getProperty("useParametricFeed")) {
      activeFeeds = initializeActiveFeeds(section);
      for (var j = 0; j < activeFeeds.length; ++j) {
        var feedContext = activeFeeds[j];
        var feedDescription = formatVariable(feedContext.description);
        if (variablesDeclaration.indexOf(feedDescription) == -1) {
          variablesDeclaration.push(feedDescription);
        }
      }
    }
  }

  if (getProperty("showOperationDialog")) {
    dropDownDialog += dropDownElements.join(", ");
    dropDownDialog += ">\", \"Select the operation to start with. \"";
    dialogsDeclaration.push(dropDownDialog);
  }
  if (!is3D() || machineConfiguration.isMultiAxisConfiguration()) {
    // submacrosDeclaration.push("Initposition");
    // submacrosDeclaration.push("Endmacro");
  }

  // variablesDeclaration.push("Curr_zpno");
  // variablesDeclaration.push("Zpos");

  if (containsProbingOperations) {
    variablesDeclaration.push("Xvalue1");
    variablesDeclaration.push("Xvalue2");
    variablesDeclaration.push("Yvalue1");
    variablesDeclaration.push("Yvalue2");
    variablesDeclaration.push("Zvalue");
    variablesDeclaration.push("Newpos");
    variablesDeclaration.push("Rotationvalue");
  }

  writeBlock("Variable " + variablesDeclaration.join(", ") + ";");
  writeln("");
  writeBlock("Smakros " + submacrosDeclaration.join(", ") + ";");
  writeln("");
  writeBlock(dialogsDeclaration.join(EOL) + ";");
  writeln("");

  if (!is3D() || machineConfiguration.isMultiAxisConfiguration()) {
    // writeBlock("_exit Endmacro;");
    // writeln("");
  }

  if (!is3D() || machineConfiguration.isMultiAxisConfiguration()) {
    // createEndmacro();
  }
}

function writeMainProgram() {

  var numberOfSections = getNumberOfSections();

  for (var i = 0; i < numberOfSections; ++i) {
    var section = getSection(i);
    var Description = getOperationDescription(section);
    var sectionID = i + 1;

    var sectionName = formatVariable("Sm_" + Description);
    var maskName = formatVariable("Op_" + Description);

    writeComment("##########" + Description + "##########");
    // writeBlock(translate("Condition") + " " + maskName + ", 0, 1, 0, " + sectionID + ";");
    writeBlock(translate("Label") + " " + sectionID + ";");

    var tool = section.getTool();
    if (getProperty("showNotes") && section.hasParameter("notes")) {
      var notes = section.getParameter("notes");
      if (notes) {
        var lines = String(notes).split("\n");
        var r1 = new RegExp("^[\\s]+", "g");
        var r2 = new RegExp("[\\s]+$", "g");
        for (line in lines) {
          var comment = lines[line].replace(r1, "").replace(r2, "");
          if (comment) {
            writeComment(comment);
          }
        }
      }
    }
    var showToolZMin = true;
    if (showToolZMin) {
      if (is3D()) {
        var zRange = section.getGlobalZRange();
        var number = tool.number;
        if (section.getTool().number != number) {
          break;
        }
        zRange.expandToRange(section.getGlobalZRange());
        writeln(localize("; ! ZMIN") + " = " + xyzFormat.format(zRange.getMinimum()) + "!");
      }
    }
    if (!isProbeOperation(section)) {
      writeBlock(translate("Tool") + " T" + (tool.number) + ", 0, 0, 1, 0;");
      writeBlock(translate("Rpm") + " 3, " + rpmFormat.format((section.getInitialSpindleSpeed() < 6000) ? 6000 : section.getInitialSpindleSpeed()) + ", 0, 30;");
    }

    // set coolant after we have positioned at Z
    setCoolant(tool.coolant);
    var t = tolerance;
    if (section.hasParameter("operation:tolerance")) {
      t = section.getParameter("operation:tolerance");
    }
    if (getProperty("useDynamic")) {
      var dynamic = 5;
      if (t <= 0.02) {
        dynamic = 4;
      }
      if (t <= 0.01) {
        dynamic = 3;
      }
      if (t <= 0.005) {
        dynamic = 2;
      }
      if (t <= 0.003) {
        dynamic = 1;
      }
      writeBlock(translate("Dynamics")  + " " + dynamic + ";");
    }
    if (getProperty("useParametricFeed")) {
      activeFeeds = initializeActiveFeeds(section);
      for (var j = 0; j < activeFeeds.length; ++j) {
        var feedContext = activeFeeds[j];
        writeBlock(formatVariable(feedContext.description) + " = " + feedFormat.format(feedContext.feed) + (unit == MM ? ";!m/min!" : ";!inch/min!"));
      }
    }

    /*
    // wcs
    var workOffset;
    if (!is3D()) {
      workOffset = 19;
      if (workOffset != currentWorkOffset) {
        writeBlock("Position " + workOffset + ", 2;");
        currentWorkOffset = workOffset;
      }
    } else {
      workOffset = section.workOffset;
      if (workOffset != 0 && workOffset < 41) {
        if (workOffset != currentWorkOffset) {
          writeBlock("Position " + workOffset + ", 2;");
          currentWorkOffset = workOffset;
        }
      }
    }
*/
    writeBlock(translate("Submacro") + " " + sectionName + ";");
  }
}

function onComment(message) {
  var comments = String(message).split(";");
  for (comment in comments) {
    writeComment(comments[comment]);
  }
}

/** Force output of X, Y, and Z. */
function forceXYZ() {
  xOutput.reset();
  yOutput.reset();
  zOutput.reset();
}

/** Force output of A, B, and C. */
function forceABC() {
  aOutput.reset();
  bOutput.reset();
  cOutput.reset();
}

function forceFeed() {
  currentFeedId = undefined;
  feedOutput.reset();
  currentFeedValue = -1;
}

/** Force output of X, Y, Z, A, B, C, and F on next output. */
function forceAny() {
  forceXYZ();
  forceABC();
  forceFeed();
}

function FeedContext(id, description, feed) {
  this.id = id;
  this.description = description;
  this.feed = feed;
}

/** Maps the specified feed value to Q feed or formatted feed. */
function getFeed(f) {
  if (activeMovements) {
    var feedContext = activeMovements[movement];
    if (feedContext != undefined) {
      if (!feedFormat.areDifferent(feedContext.feed, f)) {
        if (feedContext.id == currentFeedId) {
          return ""; // nothing has changed
        }
        forceFeed();
        currentFeedId = feedContext.id;
        return (translate("Feed") + " " + formatVariable(feedContext.description) + (Array(4).join(", " + formatVariable(feedContext.description))) + ";");
      }
    }
    currentFeedId = undefined; // force Q feed next time
  }
  if (feedFormat.areDifferent(currentFeedValue, f)) {
    currentFeedValue = f;
    return translate("Feed") + " " + feedOutput.format(f) + Array(4).join(", " + feedFormat.format(f)) + ";";
  }
  return "";
}

function initializeActiveFeeds(section) {
  var activeFeeds = new Array();
  if (section.hasAnyCycle && section.hasAnyCycle()) {
    return activeFeeds;
  }
  activeMovements = new Array();
  var movements = section.getMovements();

  var id = 0;

  if (section.hasParameter("operation:tool_feedCutting")) {
    if (movements & ((1 << MOVEMENT_CUTTING) | (1 << MOVEMENT_LINK_TRANSITION) | (1 << MOVEMENT_EXTENDED))) {
      var feedContext = new FeedContext(id, localize("Cutting"), section.getParameter("operation:tool_feedCutting"));
      activeFeeds.push(feedContext);
      activeMovements[MOVEMENT_CUTTING] = feedContext;
      activeMovements[MOVEMENT_LINK_TRANSITION] = feedContext;
      activeMovements[MOVEMENT_EXTENDED] = feedContext;
    }
    ++id;
    if (movements & (1 << MOVEMENT_PREDRILL)) {
      feedContext = new FeedContext(id, localize("Predrilling"), section.getParameter("operation:tool_feedCutting"));
      activeMovements[MOVEMENT_PREDRILL] = feedContext;
      activeFeeds.push(feedContext);
    }
    ++id;

    if (section.hasParameter("operation-strategy") && (section.getParameter("operation-strategy") == "drill")) {
      var feedContext = new FeedContext(id, localize("Cutting"), section.getParameter("operation:tool_feedCutting"));
      activeFeeds.push(feedContext);
      activeMovements[MOVEMENT_CUTTING] = feedContext;
    }
    ++id;
  }

  if (section.hasParameter("operation:finishFeedrate")) {
    if (movements & (1 << MOVEMENT_FINISH_CUTTING)) {
      var feedContext = new FeedContext(id, localize("Finish"), section.getParameter("operation:finishFeedrate"));
      activeFeeds.push(feedContext);
      activeMovements[MOVEMENT_FINISH_CUTTING] = feedContext;
    }
    ++id;
  } else if (section.hasParameter("operation:tool_feedCutting")) {
    if (movements & (1 << MOVEMENT_FINISH_CUTTING)) {
      var feedContext = new FeedContext(id, localize("Finish"), section.getParameter("operation:tool_feedCutting"));
      activeFeeds.push(feedContext);
      activeMovements[MOVEMENT_FINISH_CUTTING] = feedContext;
    }
    ++id;
  }

  if (section.hasParameter("operation:tool_feedEntry")) {
    if (movements & (1 << MOVEMENT_LEAD_IN)) {
      var feedContext = new FeedContext(id, localize("Entry"), section.getParameter("operation:tool_feedEntry"));
      activeFeeds.push(feedContext);
      activeMovements[MOVEMENT_LEAD_IN] = feedContext;
    }
    ++id;
  }

  if (section.hasParameter("operation:tool_feedExit")) {
    if (movements & (1 << MOVEMENT_LEAD_OUT)) {
      var feedContext = new FeedContext(id, localize("Exit"), section.getParameter("operation:tool_feedExit"));
      activeFeeds.push(feedContext);
      activeMovements[MOVEMENT_LEAD_OUT] = feedContext;
    }
    ++id;
  }

  if (section.hasParameter("operation:noEngagementFeedrate")) {
    if (movements & (1 << MOVEMENT_LINK_DIRECT)) {
      var feedContext = new FeedContext(id, localize("Direct"), section.getParameter("operation:noEngagementFeedrate"));
      activeFeeds.push(feedContext);
      activeMovements[MOVEMENT_LINK_DIRECT] = feedContext;
    }
    ++id;
  } else if (section.hasParameter("operation:tool_feedCutting") &&
    section.hasParameter("operation:tool_feedEntry") &&
    section.hasParameter("operation:tool_feedExit")) {
    if (movements & (1 << MOVEMENT_LINK_DIRECT)) {
      var feedContext = new FeedContext(id, localize("Direct"), Math.max(section.getParameter("operation:tool_feedCutting"), section.getParameter("operation:tool_feedEntry"), section.getParameter("operation:tool_feedExit")));
      activeFeeds.push(feedContext);
      activeMovements[MOVEMENT_LINK_DIRECT] = feedContext;
    }
    ++id;
  }

  if (section.hasParameter("operation:reducedFeedrate")) {
    if (movements & (1 << MOVEMENT_REDUCED)) {
      var feedContext = new FeedContext(id, localize("Reduced"), section.getParameter("operation:reducedFeedrate"));
      activeFeeds.push(feedContext);
      activeMovements[MOVEMENT_REDUCED] = feedContext;
    }
    ++id;
  }

  if (section.hasParameter("operation:tool_feedRamp")) {
    if (movements & ((1 << MOVEMENT_RAMP) | (1 << MOVEMENT_RAMP_HELIX) | (1 << MOVEMENT_RAMP_PROFILE) | (1 << MOVEMENT_RAMP_ZIG_ZAG))) {
      var feedContext = new FeedContext(id, localize("Ramping"), section.getParameter("operation:tool_feedRamp"));
      activeFeeds.push(feedContext);
      activeMovements[MOVEMENT_RAMP] = feedContext;
      activeMovements[MOVEMENT_RAMP_HELIX] = feedContext;
      activeMovements[MOVEMENT_RAMP_PROFILE] = feedContext;
      activeMovements[MOVEMENT_RAMP_ZIG_ZAG] = feedContext;
    }
    ++id;
  }
  if (section.hasParameter("operation:tool_feedPlunge")) {
    if (movements & (1 << MOVEMENT_PLUNGE)) {
      var feedContext = new FeedContext(id, localize("Plunge"), section.getParameter("operation:tool_feedPlunge"));
      activeFeeds.push(feedContext);
      activeMovements[MOVEMENT_PLUNGE] = feedContext;
    }
    ++id;
  }
  if (true) { // high feed
    if ((movements & (1 << MOVEMENT_HIGH_FEED)) || (highFeedMapping != HIGH_FEED_NO_MAPPING)) {
      var feed;
      if (hasParameter("operation:highFeedrateMode") && getParameter("operation:highFeedrateMode") != "disabled") {
        feed = getParameter("operation:highFeedrate");
      } else {
        feed = this.highFeedrate;
      }
      var feedContext = new FeedContext(id, localize("High Feed"), feed);
      activeFeeds.push(feedContext);
      activeMovements[MOVEMENT_HIGH_FEED] = feedContext;
      activeMovements[MOVEMENT_RAPID] = feedContext;
    }
    ++id;
  }
  return activeFeeds;
}

var currentWorkPlaneABC = undefined;

function forceWorkPlane() {
  currentWorkPlaneABC = undefined;
}

function onRewindMachine() {
  writeComment("REWIND OF MACHINE AXIS");
}

function setWorkPlane(abc, turn) {
  forceWorkPlane(); // always need the new workPlane

  if (!machineConfiguration.isMultiAxisConfiguration()) {
    return; // ignore
  }

  if (!((currentWorkPlaneABC == undefined) ||
        abcFormat.areDifferent(abc.x, currentWorkPlaneABC.x) ||
        abcFormat.areDifferent(abc.y, currentWorkPlaneABC.y) ||
        abcFormat.areDifferent(abc.z, currentWorkPlaneABC.z))) {
    return; // no change
  }

  gMotionModal.reset();

  var st = turn ? 1 : 0;
  // move origin
  var initialPosition = getFramePosition((currentSection.getInitialPosition()));
  var xv = turn ? xyzFormat.format(currentSection.isMultiAxis() ? initialPosition.x : currentSection.workOrigin.x) : xyzFormat.format(0);
  var yv = turn ? xyzFormat.format(currentSection.isMultiAxis() ? initialPosition.y : currentSection.workOrigin.y) : xyzFormat.format(0);
  var zv = turn ? xyzFormat.format(currentSection.isMultiAxis() ? initialPosition.z : currentSection.workOrigin.z) : xyzFormat.format(0);

  // rotate workplane and axis
  var xs = abcFormat.format(abc.x);
  var ys = abcFormat.format(abc.y);
  var zs = abcFormat.format(abc.z);
  var wz = turn ? 0 : 2; // 0 = indexing with retract 1= indexing with moving tool 2 = coordinate system rotation only
  var vr = feedFormat.format(10000); // feed for indexing

  if (turn) {
    writeBlock(translate("Shift") + " " + st + ", " + xv + ", " + yv + ", " + zv + ";");
    writeBlock(translate("Tilt") + " " + st + ", " + xs + ", " + ys + ", " + zs + ", " + wz + ", " + vr + ";");
  } else {
    writeBlock(translate("Tilt") + " " + st + ", " + xs + ", " + ys + ", " + zs + ", " + wz + ", " + vr + ";");
    writeBlock(translate("Shift") + " " + st + ", " + xv + ", " + yv + ", " + zv + ";");
  }

  currentWorkPlaneABC = abc;
}

var closestABC = false; // choose closest machine angles
var currentMachineABC;

function getWorkPlaneMachineABC(workPlane) {
  var W = workPlane; // map to global frame

  var abc = machineConfiguration.getABC(W);
  if (closestABC) {
    if (currentMachineABC) {
      abc = machineConfiguration.remapToABC(abc, currentMachineABC);
    } else {
      abc = machineConfiguration.getPreferredABC(abc);
    }
  } else {
    abc = machineConfiguration.getPreferredABC(abc);
  }

  try {
    abc = machineConfiguration.remapABC(abc);
    currentMachineABC = abc;
  } catch (e) {
    error(
      localize("Machine angles not supported") + ":"
      + conditional(machineConfiguration.isMachineCoordinate(0), " A" + abcFormat.format(abc.x))
      + conditional(machineConfiguration.isMachineCoordinate(1), " B" + abcFormat.format(abc.y))
      + conditional(machineConfiguration.isMachineCoordinate(2), " C" + abcFormat.format(abc.z))
    );
    return undefined;
  }

  var direction = machineConfiguration.getDirection(abc);
  if (!isSameDirection(direction, W.forward)) {
    error(localize("Orientation not supported."));
    return undefined;
  }

  if (!machineConfiguration.isABCSupported(abc)) {
    error(
      localize("Work plane is not supported") + ":"
      + conditional(machineConfiguration.isMachineCoordinate(0), " A" + abcFormat.format(abc.x))
      + conditional(machineConfiguration.isMachineCoordinate(1), " B" + abcFormat.format(abc.y))
      + conditional(machineConfiguration.isMachineCoordinate(2), " C" + abcFormat.format(abc.z))
    );
    return undefined;
  }

  var tcp = false;
  if (tcp) {
    setRotation(W); // TCP mode
  } else {
    var O = machineConfiguration.getOrientation(abc);
    var R = machineConfiguration.getRemainingOrientation(abc, W);
    setRotation(R);
  }

  return abc;
}

function isProbeOperation(section) {
  return section.hasParameter("operation-strategy") && (section.getParameter("operation-strategy") == "probe");
}

function onSection() {
  var forceToolAndRetract = optionalSection && !currentSection.isOptional();
  optionalSection = currentSection.isOptional();

  var insertToolCall = forceToolAndRetract || isFirstSection() ||
    currentSection.getForceToolChange && currentSection.getForceToolChange() ||
    (tool.number != getPreviousSection().getTool().number);

  retracted = false;
  var newWorkOffset = isFirstSection() ||
    (getPreviousSection().workOffset != currentSection.workOffset); // work offset changes
  var newWorkPlane = isFirstSection() ||
    !isSameDirection(getPreviousSection().getGlobalFinalToolAxis(), currentSection.getGlobalInitialToolAxis()) ||
    (currentSection.isOptimizedForMachine() && getPreviousSection().isOptimizedForMachine() &&
      Vector.diff(getPreviousSection().getFinalToolAxisABC(), currentSection.getInitialToolAxisABC()).length > 1e-4) ||
    (!machineConfiguration.isMultiAxisConfiguration() && currentSection.isMultiAxis()) ||
    (!getPreviousSection().isMultiAxis() && currentSection.isMultiAxis() ||
      getPreviousSection().isMultiAxis() && !currentSection.isMultiAxis()); // force newWorkPlane between indexing and simultaneous operations
  writeBlock("(");

  if (insertToolCall || newWorkOffset || newWorkPlane) {
    // retract to safe plane
    writeBlock(translate("ToolRetraction") + ";");
    forceXYZ();
  }

  if (insertToolCall) {
    forceWorkPlane();

    if (tool.number > 99) {
      warning(localize("Tool number exceeds maximum value."));
    }
  }

  if (insertToolCall ||
      forceSpindleSpeed ||
      isFirstSection() ||
      (rpmFormat.areDifferent(spindleSpeed, sOutput.getCurrent())) ||
      (tool.clockwise != getPreviousSection().getTool().clockwise)) {
    forceSpindleSpeed = false;

    if (spindleSpeed > 60000) {
      warning(localize("Spindle speed exceeds maximum value."));
    }
    if (!tool.clockwise) {
      error(localize("Spindle direction not supported."));
      return;
    }
  }

  forceXYZ();

  if (machineConfiguration.isMultiAxisConfiguration()) { // use 5-axis indexing for multi-axis mode
    // set working plane after datum shift

    if (currentSection.isMultiAxis()) {
      forceWorkPlane();
      cancelTransformation();
      if (!retracted) {
        writeRetract(Z);
      }
    } else {
      var eulerXYZ = currentSection.workPlane.getTransposed().eulerZYX_R;
      var abc = new Vector(-eulerXYZ.x, -eulerXYZ.y, -eulerXYZ.z);
      setWorkPlane(abc, true);
    }
  } else { // pure 3D
    var remaining = currentSection.workPlane;
    if (!isSameDirection(remaining.forward, new Vector(0, 0, 1)) || currentSection.isMultiAxis()) {
      //error(localize("Tool orientation is not supported."));
      error(translate(
        "\r\n________________________________________" +
        "\r\n|              error                    |" +
        "\r\n|                                       |" +
        "\r\n| 4/5 axis operations detected.         |" +
        "\r\n| You have to enable the property       |" +
        "\r\n| got4thAxis or got5Axis,               |" +
        "\r\n| otherwise you can only post           |" +
        "\r\n| 3 Axis programs.                      |" +
        "\r\n| If you still have issues,             |" +
        "\r\n| please contact www.DATRON.com!        |" +
        "\r\n|_______________________________________|\r\n"));
      return;
    }
    setRotation(remaining);
  }

  forceAny();

  var t = tolerance;
  if (hasParameter("operation:tolerance")) {
    if (t < getParameter("operation:tolerance")) {
      t = getParameter("operation:tolerance");
    }
  }
  if (getProperty("useSmoothing") && !isProbeOperation(currentSection)) {
    writeBlock(translate("Contour_smoothing") + " 1, " + xyzFormat.format(t * 1.2) + ", 0.1, 110, 1;");
  }

  var initialPosition = getFramePosition(currentSection.getInitialPosition());
  if (!retracted) {
    if (getCurrentPosition().z < initialPosition.z) {
      writeRetract(Z);
    }
  }

  if (currentSection.isMultiAxis()) {
    var abc = currentSection.getInitialToolAxisABC();
    writeComment("Prepositioning start");
    setWorkPlane(abc, true);
    writeBlock(gMotionModal.format(1), xyzFormat.format(0) + ", " + xyzFormat.format(0) + ", " + "z6p" + ";");
    writeBlock(gMotionModal.format(1), "x6p" + ", " + "y6p" + ", " + xyzFormat.format(0) + ";");
    setWorkPlane(new Vector(0, 0, 0), false);
    writeComment("Prepositioning end");
    cancelTransformation();
    forceWorkPlane();
    if (currentSection.getOptimizedTCPMode() == 0) {
      writeBlock("Rtcp 1;");
    }
  } else {
    writeBlock(gMotionModal.format(1), xOutput.format(initialPosition.x) + ", " + yOutput.format(initialPosition.y) + ", " + "z6p"  + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(initialPosition.x) + ", " + yOutput.format(initialPosition.y) + ", " + zOutput.format(initialPosition.z) + ", 0, 0;");
  }

  if (getProperty("useParametricFeed") /*&&
      hasParameter("operation-strategy") &&
      (getParameter("operation-strategy") != "drill")*/ &&
      !(currentSection.hasAnyCycle && currentSection.hasAnyCycle())) {
    if (!insertToolCall &&
        activeMovements &&
        (getCurrentSectionId() > 0) &&
        (getPreviousSection().getPatternId() == currentSection.getPatternId()) && (currentSection.getPatternId() != 0)) {
      // use the current feeds
    } else {
      initializeActiveFeeds(currentSection);
    }
  } else {
    activeMovements = undefined;
  }
}

function onDwell(seconds) {
  writeln(localize("Dwell") + " " + secFormat.format(seconds) + ", 0, 0, 0, 0, 0, 0;");
}

function onSpindleSpeed(spindleSpeed) {
  writeBlock(translate("Rpm") + " 3, " + rpmFormat.format((spindleSpeed < 6000) ? 6000 : spindleSpeed) + ", 0, 30;");
}

function onCycle() {
}

/** Convert approach to sign. */
function approach(value) {
  validate((value == "positive") || (value == "negative"), "Invalid approach.");
  return (value == "positive") ? 1 : -1;
}

function onCyclePoint(x, y, z) {
  if (!isSameDirection(getRotation().forward, new Vector(0, 0, 1))) {
    expandCyclePoint(x, y, z);
    return;
  }
  writeBlock(getFeed(cycle.feedrate));

  if (isProbeOperation(currentSection)) {
    if (!isSameDirection(currentSection.workPlane.forward, new Vector(0, 0, 1))) {
      if (!allowIndexingWCSProbing && currentSection.strategy == "probe") {
        error(localize("Updating WCS / work offset using probing is only supported by the CNC in the WCS frame."));
        return;
      }
    }

    forceXYZ();
  }

  switch (cycleType) {
  case "bore-milling":
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.clearance) + ",0,0;");
    mcrBoreMilling(cycle);
    break;
  case "thread-milling":
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.clearance) + ",0,0;");
    mcrThreadMilling(cycle);
    break;
  case "probing-x":
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    var touchPositionX1 = x + approach(cycle.approach1) * (cycle.probeClearance + tool.diameter / 2 + cycle.probeOvertravel);
    writeBlock("Xvalue1 = " + touchPositionX1 + ";");
    writeBlock("Taxyz 2, Xvalue1, Y6p, Z6p, 1, 0, 0;");
    writeBlock("Newpos = X6p + (" + xOutput.format(x + approach(cycle.approach1) * (cycle.probeClearance + tool.diameter / 2)) + ") - Xvalue1;");
    writeBlock(translate("Setzp") + " Newpos, Y6p, Z6p;");
    break;
  case "probing-y":
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    var touchPositionY1 = y + approach(cycle.approach1) * (cycle.probeClearance + tool.diameter / 2 + cycle.probeOvertravel);
    writeBlock("Yvalue1 = " + touchPositionY1 + ";");
    writeBlock("Taxyz 2, X6p, Yvalue1, Z6p, 1, 0, 0;");
    writeBlock("Newpos = Y6p + (" + yOutput.format(y + approach(cycle.approach1) * (cycle.probeClearance + tool.diameter / 2)) + ") - Yvalue1;");
    writeBlock(translate("Setzp") + " X6p, Newpos, Z6p;");
    break;
  case "probing-z":
    var zpos = zOutput.format(Math.min(z - cycle.depth + cycle.probeClearance, cycle.retract));
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zpos + ", 0, 0;");
    writeBlock(translate("Zheight") + " 0, 0, 1, 0, " + zpos + ", " + zpos + ";");
    break;
  case "probing-x-wall":
    var touchPositionX1 = x + cycle.width1 / 2 + (tool.diameter / 2 - cycle.probeOvertravel);
    var touchPositionX2 = x - cycle.width1 / 2 - (tool.diameter / 2 - cycle.probeOvertravel);

    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x + cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x + cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock("Xvalue1 = " + xyzFormat.format(touchPositionX1) + ";");
    writeBlock("Taxyz 2, Xvalue1, Y6p, Z6p, 1, 0, 0;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x - cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x - cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock("Xvalue2 = " + xyzFormat.format(touchPositionX2) + ";");
    writeBlock("Taxyz 2, Xvalue2, Y6p, Z6p, 1, 0, 0;");
    writeBlock("Newpos = x6p + " + xOutput.format(x) + " - (Xvalue1 + Xvalue2) / 2;");
    writeBlock(translate("Setzp") + " Newpos, Y6p, Z6p;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    break;
  case "probing-y-wall":
    var touchPositionY1 = y + cycle.width1 / 2 + (tool.diameter / 2 - cycle.probeOvertravel);
    var touchPositionY2 = y - cycle.width1 / 2 - (tool.diameter / 2 - cycle.probeOvertravel);

    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y + cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y + cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock("Yvalue1 = " + xyzFormat.format(touchPositionY1) + ";");
    writeBlock("Taxyz 2, X6p, Yvalue1, Z6p, 1, 0, 0;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y - cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y - cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock("Yvalue2 = " + xyzFormat.format(touchPositionY2) + ";");
    writeBlock("Taxyz 2, X6p, Yvalue2, Z6p, 1, 0, 0;");
    writeBlock("Newpos = y6p + " + yOutput.format(y) + " - (Yvalue1 + Yvalue2) / 2;");
    writeBlock(translate("Setzp") + " X6p, Newpos, Z6p;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    break;
  case "probing-x-channel":
    var touchPositionX1 = x + (cycle.width1 / 2 + cycle.probeOvertravel);
    var touchPositionX2 = x - (cycle.width1 / 2 + cycle.probeOvertravel);

    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock("Xvalue1 = " + xyzFormat.format(touchPositionX1) + ";");
    writeBlock("Taxyz 2, Xvalue1, Y6p, Z6p, 1, 0, 0;");
    writeBlock("Xvalue2 = " + xyzFormat.format(touchPositionX2) + ";");
    writeBlock("Taxyz 2, Xvalue2, Y6p, Z6p, 1, 0, 0;");
    writeBlock("Newpos = x6p + " + xOutput.format(x) + " - (Xvalue1 + Xvalue2) / 2;");
    writeBlock(translate("Setzp") + " Newpos, Y6p, Z6p;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    break;
  case "probing-x-channel-with-island":
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x + cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x + cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");

    var touchPositionX1 = xOutput.getCurrent() + cycle.probeClearance + cycle.probeOvertravel;
    writeBlock("Xvalue1 = " + xyzFormat.format(touchPositionX1) + ";");
    writeBlock("Taxyz 2, Xvalue1, Y6p, Z6p, 1, 0, 0;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x - cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x - cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");

    var touchPositionX2 = xOutput.getCurrent() - cycle.probeClearance - cycle.probeOvertravel;
    writeBlock("Xvalue2 = " + xyzFormat.format(touchPositionX2) + ";");
    writeBlock("Taxyz 2, Xvalue2, Y6p, Z6p, 1, 0, 0;");
    writeBlock("Newpos = x6p + " + xOutput.format(x) + " - (Xvalue1 + Xvalue2) / 2;");
    writeBlock(translate("Setzp") + " Newpos, Y6p, Z6p;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    break;
  case "probing-y-channel":
    var touchPositionY1 = y + (cycle.width1 / 2 + cycle.probeOvertravel);
    var touchPositionY2 = y - (cycle.width1 / 2 + cycle.probeOvertravel);

    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock("Yvalue1 = " + xyzFormat.format(touchPositionY1) + ";");
    writeBlock("Taxyz 2, x6p, Yvalue1, Z6p, 1, 0, 0;");
    writeBlock("Yvalue2 = " + xyzFormat.format(touchPositionY2) + ";");
    writeBlock("Taxyz 2, x6p, Yvalue2, Z6p, 1, 0, 0;");
    writeBlock("Newpos = y6p + " + yOutput.format(y) + " - (Yvalue1 + Yvalue2) / 2;");
    writeBlock(translate("Setzp") + " x6p, Newpos, Z6p;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    break;
  case "probing-y-channel-with-island":
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y + cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y + cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");

    var touchPositionY1 = yOutput.getCurrent() + cycle.probeClearance + cycle.probeOvertravel;
    writeBlock("Yvalue1 = " + xyzFormat.format(touchPositionY1) + ";");
    writeBlock("Taxyz 2, x6p, Yvalue1, Z6p, 1, 0, 0;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y - cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y - cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");

    var touchPositionY2 = yOutput.getCurrent() - cycle.probeClearance - cycle.probeOvertravel;
    writeBlock("Yvalue2 = " + xyzFormat.format(touchPositionY2) + ";");
    writeBlock("Taxyz 2, x6p, Yvalue2, Z6p, 1, 0, 0;");
    writeBlock("Newpos = y6p + " + yOutput.format(y) + " - (Yvalue1 + Yvalue2) / 2;");
    writeBlock(translate("Setzp") + " x6p, Newpos, Z6p;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    break;
  case "probing-xy-circular-boss":
    // X positions
    var touchPositionX1 = x + cycle.width1 / 2 + (tool.diameter / 2 - cycle.probeOvertravel); // this might be wrong
    var touchPositionX2 = x - cycle.width1 / 2 - (tool.diameter / 2 - cycle.probeOvertravel); // this might be wrong

    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x + cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x + cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock("Xvalue1 = " + xyzFormat.format(touchPositionX1) + ";");
    writeBlock("Taxyz 2, Xvalue1, Y6p, Z6p, 1, 0, 0;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x - cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x - cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock("Xvalue2 = " + xyzFormat.format(touchPositionX2) + ";");
    writeBlock("Taxyz 2, Xvalue2, Y6p, Z6p, 1, 0, 0;");
    writeBlock("Newpos = x6p + " + xOutput.format(x) + " - (Xvalue1 + Xvalue2) / 2;");
    writeBlock(translate("Setzp") + " Newpos, Y6p, Z6p;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");

    // Y positions
    forceXYZ();
    var touchPositionY1 = y + cycle.width1 / 2 + (tool.diameter / 2 - cycle.probeOvertravel);
    var touchPositionY2 = y - cycle.width1 / 2 - (tool.diameter / 2 - cycle.probeOvertravel);

    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y + cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y + cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock("Yvalue1 = " + xyzFormat.format(touchPositionY1) + ";");
    writeBlock("Taxyz 2, X6p, Yvalue1, Z6p, 1, 0, 0;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y - cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y - cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock("Yvalue2 = " + xyzFormat.format(touchPositionY2) + ";");
    writeBlock("Taxyz 2, X6p, Yvalue2, Z6p, 1, 0, 0;");
    writeBlock("Newpos = y6p + " + yOutput.format(y) + " - (Yvalue1 + Yvalue2) / 2;");
    writeBlock(translate("Setzp") + " X6p, Newpos, Z6p;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    break;
  case "probing-xy-circular-hole":
    // X positions
    var touchPositionX1 = x + (cycle.width1 / 2 + cycle.probeOvertravel - tool.diameter / 2);
    var touchPositionX2 = x - (cycle.width1 / 2 + cycle.probeOvertravel - tool.diameter / 2);

    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock("Xvalue1 = " + xyzFormat.format(touchPositionX1) + ";");
    writeBlock("Taxyz 2, Xvalue1, Y6p, Z6p, 1, 0, 0;");
    writeBlock("Xvalue2 = " + xyzFormat.format(touchPositionX2) + ";");
    writeBlock("Taxyz 2, Xvalue2, Y6p, Z6p, 1, 0, 0;");
    writeBlock("Newpos = x6p + " + xOutput.format(x) + " - (Xvalue1 + Xvalue2) / 2;");
    writeBlock(translate("Setzp") + " Newpos, Y6p, Z6p;");

    // Y positions
    forceXYZ();
    var touchPositionY1 = y + (cycle.width1 / 2 + cycle.probeOvertravel - tool.diameter / 2);
    var touchPositionY2 = y - (cycle.width1 / 2 + cycle.probeOvertravel - tool.diameter / 2);

    writeBlock("Yvalue1 = " + xyzFormat.format(touchPositionY1) + ";");
    writeBlock("Taxyz 2, X6p, Yvalue1, Z6p, 1, 0, 0;");
    writeBlock("Yvalue2 = " + xyzFormat.format(touchPositionY2) + ";");
    writeBlock("Taxyz 2, X6p, Yvalue2, Z6p, 1, 0, 0;");
    writeBlock("Newpos = y6p + " + yOutput.format(y) + " - (Yvalue1 + Yvalue2) / 2;");
    writeBlock(translate("Setzp") + " X6p, Newpos, Z6p;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    break;
  case "probing-xy-circular-hole-with-island":
    // X positions
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x + cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x + cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");

    var touchPositionX1 = xOutput.getCurrent() + cycle.probeClearance + cycle.probeOvertravel;
    writeBlock("Xvalue1 = " + xyzFormat.format(touchPositionX1) + ";");
    writeBlock("Taxyz 2, Xvalue1, Y6p, Z6p, 1, 0, 0;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x - cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x - cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");

    var touchPositionX2 = xOutput.getCurrent() - cycle.probeClearance - cycle.probeOvertravel;
    writeBlock("Xvalue2 = " + xyzFormat.format(touchPositionX2) + ";");
    writeBlock("Taxyz 2, Xvalue2, Y6p, Z6p, 1, 0, 0;");
    writeBlock("Newpos = x6p + " + xOutput.format(x) + " - (Xvalue1 + Xvalue2) / 2;");
    writeBlock(translate("Setzp") + " Newpos, Y6p, Z6p;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");

    // Y positions
    forceXYZ();
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y + cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y + cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");

    var touchPositionY1 = yOutput.getCurrent() + cycle.probeClearance + cycle.probeOvertravel;
    writeBlock("Yvalue1 = " + xyzFormat.format(touchPositionY1) + ";");
    writeBlock("Taxyz 2, x6p, Yvalue1, Z6p, 1, 0, 0;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y - cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y - cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");

    var touchPositionY2 = yOutput.getCurrent() - cycle.probeClearance - cycle.probeOvertravel;
    writeBlock("Yvalue2 = " + xyzFormat.format(touchPositionY2) + ";");
    writeBlock("Taxyz 2, x6p, Yvalue2, Z6p, 1, 0, 0;");
    writeBlock("Newpos = y6p + " + yOutput.format(y) + " - (Yvalue1 + Yvalue2) / 2;");
    writeBlock(translate("Setzp") + " x6p, Newpos, Z6p;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    break;
  case "probing-xy-rectangular-boss":
    // X positions
    var touchPositionX1 = x + cycle.width1 / 2 + (tool.diameter / 2 - cycle.probeOvertravel); // this might be wrong
    var touchPositionX2 = x - cycle.width1 / 2 - (tool.diameter / 2 - cycle.probeOvertravel); // this might be wrong

    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x + cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x + cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock("Xvalue1 = " + xyzFormat.format(touchPositionX1) + ";");
    writeBlock("Taxyz 2, Xvalue1, Y6p, Z6p, 1, 0, 0;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x - cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x - cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock("Xvalue2 = " + xyzFormat.format(touchPositionX2) + ";");
    writeBlock("Taxyz 2, Xvalue2, Y6p, Z6p, 1, 0, 0;");
    writeBlock("Newpos = x6p + " + xOutput.format(x) + " - (Xvalue1 + Xvalue2) / 2;");
    writeBlock(translate("Setzp") + " Newpos, Y6p, Z6p;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");

    // Y positions
    var touchPositionY1 = y + cycle.width2 / 2 + (tool.diameter / 2 - cycle.probeOvertravel);
    var touchPositionY2 = y - cycle.width2 / 2 - (tool.diameter / 2 - cycle.probeOvertravel);

    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y + cycle.width2 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y + cycle.width2 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock("Yvalue1 = " + xyzFormat.format(touchPositionY1) + ";");
    writeBlock("Taxyz 2, X6p, Yvalue1, Z6p, 1, 0, 0;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y - cycle.width2 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y - cycle.width2 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock("Yvalue2 = " + xyzFormat.format(touchPositionY2) + ";");
    writeBlock("Taxyz 2, X6p, Yvalue2, Z6p, 1, 0, 0;");
    writeBlock("Newpos = y6p + " + yOutput.format(y) + " - (Yvalue1 + Yvalue2) / 2;");
    writeBlock(translate("Setzp") + " X6p, Newpos, Z6p;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    break;
  case "probing-xy-rectangular-hole":
    // X positions
    var touchPositionX1 = x + (cycle.width1 / 2 + cycle.probeOvertravel - tool.diameter / 2);
    var touchPositionX2 = x - (cycle.width1 / 2 + cycle.probeOvertravel - tool.diameter / 2);

    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock("Xvalue1 = " + xyzFormat.format(touchPositionX1) + ";");
    writeBlock("Taxyz 2, Xvalue1, Y6p, Z6p, 1, 0, 0;");
    writeBlock("Xvalue2 = " + xyzFormat.format(touchPositionX2) + ";");
    writeBlock("Taxyz 2, Xvalue2, Y6p, Z6p, 1, 0, 0;");
    writeBlock("Newpos = x6p + " + xOutput.format(x) + " - (Xvalue1 + Xvalue2) / 2;");
    writeBlock(translate("Setzp") + " Newpos, Y6p, Z6p;");

    // Y positions
    forceXYZ();
    var touchPositionY1 = y + (cycle.width2 / 2 + cycle.probeOvertravel - tool.diameter / 2);
    var touchPositionY2 = y - (cycle.width2 / 2 + cycle.probeOvertravel - tool.diameter / 2);

    writeBlock("Yvalue1 = " + xyzFormat.format(touchPositionY1) + ";");
    writeBlock("Taxyz 2, X6p, Yvalue1, Z6p, 1, 0, 0;");
    writeBlock("Yvalue2 = " + xyzFormat.format(touchPositionY2) + ";");
    writeBlock("Taxyz 2, X6p, Yvalue2, Z6p, 1, 0, 0;");
    writeBlock("Newpos = y6p + " + yOutput.format(y) + " - (Yvalue1 + Yvalue2) / 2;");
    writeBlock(translate("Setzp") + " X6p, Newpos, Z6p;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    break;
  case "probing-xy-rectangular-hole-with-island":
    // X positions
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x + cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x + cycle.width1 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");

    var touchPositionX1 = xOutput.getCurrent() + cycle.probeClearance + cycle.probeOvertravel;
    writeBlock("Xvalue1 = " + xyzFormat.format(touchPositionX1) + ";");
    writeBlock("Taxyz 2, Xvalue1, Y6p, Z6p, 1, 0, 0;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x - cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x - cycle.width1 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");

    var touchPositionX2 = xOutput.getCurrent() - cycle.probeClearance - cycle.probeOvertravel;
    writeBlock("Xvalue2 = " + xyzFormat.format(touchPositionX2) + ";");
    writeBlock("Taxyz 2, Xvalue2, Y6p, Z6p, 1, 0, 0;");
    writeBlock("Newpos = x6p + " + xOutput.format(x) + " - (Xvalue1 + Xvalue2) / 2;");
    writeBlock(translate("Setzp") + " Newpos, Y6p, Z6p;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");

    // Y positions
    forceXYZ();
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y + cycle.width2 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y + cycle.width2 / 2 - (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");

    var touchPositionY1 = yOutput.getCurrent() + cycle.probeClearance + cycle.probeOvertravel;
    writeBlock("Yvalue1 = " + xyzFormat.format(touchPositionY1) + ";");
    writeBlock("Taxyz 2, x6p, Yvalue1, Z6p, 1, 0, 0;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y - cycle.width2 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y - cycle.width2 / 2 + (cycle.probeClearance + tool.diameter / 2)) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");

    var touchPositionY2 = yOutput.getCurrent() - cycle.probeClearance - cycle.probeOvertravel;
    writeBlock("Yvalue2 = " + xyzFormat.format(touchPositionY2) + ";");
    writeBlock("Taxyz 2, x6p, Yvalue2, Z6p, 1, 0, 0;");
    writeBlock("Newpos = y6p + " + yOutput.format(y) + " - (Yvalue1 + Yvalue2) / 2;");
    writeBlock(translate("Setzp") + " x6p, Newpos, Z6p;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    break;
  case "probing-xy-inner-corner":
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");

    var touchPositionX1 = x + approach(cycle.approach1) * (cycle.probeClearance + tool.diameter / 2 + cycle.probeOvertravel);
    writeBlock("Xvalue1 = " + touchPositionX1 + ";");
    writeBlock("Taxyz 2, Xvalue1, Y6p, Z6p, 1, 0, 0;");
    writeBlock("Newpos = X6p + (" + xOutput.format(x + approach(cycle.approach1) * (cycle.probeClearance + tool.diameter / 2)) + ") - Xvalue1;");
    writeBlock(translate("Setzp") + " Newpos, Y6p, Z6p;");

    // Y position
    forceXYZ();
    var touchPositionY1 = y + approach(cycle.approach2) * (cycle.probeClearance + tool.diameter / 2 + cycle.probeOvertravel);
    writeBlock("Yvalue1 = " + touchPositionY1 + ";");
    writeBlock("Taxyz 2, X6p, Yvalue1, Z6p, 1, 0, 0;");
    writeBlock("Newpos = Y6p + (" + yOutput.format(y + approach(cycle.approach2) * (cycle.probeClearance + tool.diameter / 2)) + ") - Yvalue1;");
    writeBlock(translate("Setzp") + " X6p, Newpos, Z6p;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    break;
  case "probing-xy-outer-corner":
    // X position
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y * -1) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    var touchPositionX1 = x + approach(cycle.approach1) * (cycle.probeClearance + tool.diameter / 2 + cycle.probeOvertravel);
    writeBlock("Xvalue1 = " + touchPositionX1 + ";");
    writeBlock("Taxyz 2, Xvalue1, Y6p, Z6p, 1, 0, 0;");
    writeBlock("Newpos = X6p + (" + xOutput.format(x + approach(cycle.approach1) * (cycle.probeClearance + tool.diameter / 2)) + ") - Xvalue1;");
    writeBlock(translate("Setzp") + " Newpos, Y6p, Z6p;");

    // Y position
    forceXYZ();
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x * -1) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    var touchPositionY1 = y + approach(cycle.approach2) * (cycle.probeClearance + tool.diameter / 2 + cycle.probeOvertravel);
    writeBlock("Yvalue1 = " + touchPositionY1 + ";");
    writeBlock("Taxyz 2, X6p, Yvalue1, Z6p, 1, 0, 0;");
    writeBlock("Newpos = Y6p + (" + yOutput.format(y + approach(cycle.approach2) * (cycle.probeClearance + tool.diameter / 2)) + ") - Yvalue1;");
    writeBlock(translate("Setzp") + " X6p, Newpos, Z6p;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    break;
  case "probing-x-plane-angle":
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y + cycle.probeSpacing / 2) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y + cycle.probeSpacing / 2) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");

    var touchPositionX1 = x + approach(cycle.approach1) * (cycle.probeClearance + tool.diameter / 2 + cycle.probeOvertravel);
    var touchPositionX2 = touchPositionX1;
    writeBlock("Xvalue1 = " + touchPositionX1 + ";");
    writeBlock("Xvalue2 = " + touchPositionX2 + ";");
    writeBlock("Taxyz 2, Xvalue1, Y6p, Z6p, 1, 0, 0;");
    writeBlock(gMotionModal.format(1), "x6p" + ", " + "y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y - cycle.probeSpacing / 2) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x) + ", " + yOutput.format(y - cycle.probeSpacing / 2) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock("Taxyz 2, Xvalue2, Y6p, Z6p, 1, 0, 0;");
    writeBlock("Rotationvalue = Arctan ( ( Xvalue2 - Xvalue1 ) / " + "(" + (y + cycle.probeSpacing / 2) + "-" + (y - cycle.probeSpacing / 2) + ") );");
    writeBlock(translate("Rotation") + " Rotationvalue, 1, 1, 1, 0, 0;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    break;
  case "probing-y-plane-angle":
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x + cycle.probeSpacing / 2) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x + cycle.probeSpacing / 2) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");

    var touchPositionY1 = y + approach(cycle.approach1) * (cycle.probeClearance + tool.diameter / 2 + cycle.probeOvertravel);
    var touchPositionY2 = touchPositionY1;
    writeBlock("Yvalue1 = " + touchPositionY1 + ";");
    writeBlock("Yvalue2 = " + touchPositionY2 + ";");
    writeBlock("Taxyz 2, X6p, Yvalue1, Z6p, 1, 0, 0;");
    writeBlock(gMotionModal.format(1), "x6p" + ", " + "y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x - cycle.probeSpacing / 2) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(0), xOutput.format(x - cycle.probeSpacing / 2) + ", " + yOutput.format(y) + ", " + zOutput.format(z - cycle.depth) + ", 0, 0;");
    writeBlock("Taxyz 2, X6p, Yvalue2, Z6p, 1, 0, 0;");
    writeBlock("Rotationvalue = Arctan ( ( Yvalue2 - Yvalue1 ) / " + "(" + (x + cycle.probeSpacing / 2) + "-" + (x - cycle.probeSpacing / 2) + ") );");
    writeBlock(translate("Rotation") + " Rotationvalue, 1, 1, 1, 0, 0;");
    writeBlock(gMotionModal.format(1), "X6p, Y6p" + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    writeBlock(gMotionModal.format(1), xOutput.format(x) + ", " + yOutput.format(y) + ", " + zOutput.format(cycle.stock) + ", 0, 0;");
    break;
  default:
    expandCyclePoint(x, y, z);
  }
}

function mcrBoreMilling(cycle) {
  var numberOfSteps = (cycle.numberOfSteps != undefined) ? cycle.numberOfSteps : 0;
  if (numberOfSteps > 2) {
    error(localize("Only 2 steps are allowed for bore-milling"));
    return;
  }

  var helixCycles = Math.floor(cycle.depth / cycle.pitch); // needs to be tested
  var XYCleaning = (numberOfSteps == 2) ? cycle.stepover : 0;
  var bottomCleaning = 0;
  var fastZPlunge = cycle.clearance - cycle.retract;
  var slowZPlunge = cycle.retract - cycle.stock;
  var maxZDepthPerStep = tool.fluteLength * 0.8;

  var block = subst(localize("Drill") + " %1, %5, %2, %3, %4, 1, %6, %7, %8;",
    xyzFormat.format(fastZPlunge),
    xyzFormat.format(cycle.diameter),
    helixCycles,
    xyzFormat.format(XYCleaning),
    xyzFormat.format(slowZPlunge),
    bottomCleaning,
    xyzFormat.format(cycle.depth),
    xyzFormat.format(maxZDepthPerStep)
  );

  writeBlock(block);
}

function mcrThreadMilling(cycle) {
  var fastZPlunge = cycle.clearance - cycle.retract;
  var slowZPlunge = cycle.retract - cycle.stock;
  var threadDirection = (cycle.threading == "right") ? 1 : -1;

  var stringSubst = new StringSubstitution();
  stringSubst.setValue("ThreadNorm", 0);
  stringSubst.setValue("ThreadMillingDirection", 0);
  stringSubst.setValue("ThreadDiameter", xyzFormat.format(cycle.diameter * threadDirection));
  stringSubst.setValue("InnerOuter", 1);
  stringSubst.setValue("Pitch", xyzFormat.format(cycle.pitch));
  stringSubst.setValue("HoleDepth", xyzFormat.format(cycle.depth + 1));
  stringSubst.setValue("ThreadDepth", xyzFormat.format(cycle.depth));
  stringSubst.setValue("CleanXY", xyzFormat.format(cycle.repeatPass));
  stringSubst.setValue("FastZMove", xyzFormat.format(fastZPlunge));
  stringSubst.setValue("SlowZMove", xyzFormat.format(slowZPlunge));
  stringSubst.setValue("ThreadMillAngle", 60);
  stringSubst.setValue("Predrill", 0);
  stringSubst.setValue("ThreadID", 0);
  stringSubst.setValue("Sink", 1); // 0 = with sink, 1 = without sink

  writeBlock(
    stringSubst.substitute(translate("Thread") + " ${ThreadNorm}, ${ThreadMillingDirection}, ${ThreadDiameter}, ${InnerOuter}, ${Pitch}, ${HoleDepth}, ${ThreadDepth}, ${CleanXY}, ${FastZMove}, ${SlowZMove}, ${ThreadMillAngle}, ${Predrill}, ${Sink}, ${ThreadID};")
  );
}

/** Implement G93 command. */
function mcrSetInverseTimeFeed() {
  directWriteToCNC("G93");
}

/** Implement G94 command. */
function mcrSetTimeFeed() {
  directWriteToCNC("G94");
}

/** Write a command to the cnc kernel without interpretation from the control DANGEROUS. */
function directWriteToCNC(command) {
  error(localize("Inverse Time feed is currently not supported."));
  return;
}

function onCycleEnd() {
  if (!cycleExpanded) {
    zOutput.reset();
  }

  var probeWorkOffsetCode;
  if (isProbeOperation(currentSection)) {
    var probeOutputWorkOffset = currentSection.probeWorkOffset;
    var workOffset = probeOutputWorkOffset ? probeOutputWorkOffset : currentWorkOffset;
    if (workOffset != 0) {
      if (workOffset >= 19) {
        error(localize("Work offset is out of range."));
        return;
      }
      probeWorkOffsetCode = workOffset;
      writeBlock("Position " + probeWorkOffsetCode + ", 3;");
    }
    forceXYZ();
  }
}

var pendingRadiusCompensation = -1;

function onRadiusCompensation() {
  pendingRadiusCompensation = radiusCompensation;
}

function onRapid(_x, _y, _z) {
  var xyz = xOutput.format(_x) + ", " + yOutput.format(_y) + ", " + zOutput.format(_z);
  if (xyz) {
    if (pendingRadiusCompensation >= 0) {
      error(localize("Radius compensation mode cannot be changed at rapid traversal."));
      return;
    }
    writeBlock(gMotionModal.format(1), xyz + ", 0, 0;");
    forceFeed();
  }
}

function onLinear(_x, _y, _z, feed) {
  var xyz = xOutput.format(_x) + ", " + yOutput.format(_y) + ", " + zOutput.format(_z);
  var f = getFeed(feed);

  if (f) {
    writeBlock(f);
  }
  if (xyz) {
    if (pendingRadiusCompensation >= 0) {
      pendingRadiusCompensation = -1;
      switch (radiusCompensation) {
      case RADIUS_COMPENSATION_LEFT:
        writeBlock(translate("Tcomp") + " 1," + " 0, 0, 1, 1;");
        writeBlock(gMotionModal.format(0), xyz + ", 0, 0;");
        break;
      case RADIUS_COMPENSATION_RIGHT:
        writeBlock(translate("Tcomp") + " 2," + " 0, 0, 1, 1;");
        writeBlock(gMotionModal.format(0), xyz + ", 0, 0;");
        break;
      default:
        writeBlock(translate("Tcomp") + " 0," + " 0, 0, 1, 1;");
        writeBlock(gMotionModal.format(0), xyz + ", 0, 0;");
      }
    } else {
      writeBlock(gMotionModal.format(0), xyz + ", 0, 0;");
    }
  } else if (f) {
    if (getNextRecord().isMotion()) { // try not to output feed without motion
      forceFeed(); // force feed on next line
    } else {
      writeBlock(gMotionModal.format(0), f);
    }
  }
}

function onRapid5D(_x, _y, _z, _a, _b, _c) {
  if (pendingRadiusCompensation >= 0) {
    error(localize("Radius compensation mode cannot be changed at rapid traversal."));
    return;
  }

  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  var a = (machineConfiguration.isMachineCoordinate(0) ? aOutput.format(_a) : "a6p");
  var b = (machineConfiguration.isMachineCoordinate(1) ? bOutput.format(_b) : "b6p");
  var c = (machineConfiguration.isMachineCoordinate(2) ? cOutput.format(_c) : "c6p");

  forceXYZ();
  writeBlock("Axyzabc 1, " + x + ", " + y + ", " + z + ", " + a + ", " + b + ", " + c + ";");

  forceFeed();
}

function onLinear5D(_x, _y, _z, _a, _b, _c, feed) {
  if (pendingRadiusCompensation >= 0) {
    error(localize("Radius compensation cannot be activated/deactivated for 5-axis move."));
    return;
  }

  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  var a = (machineConfiguration.isMachineCoordinate(0) ? aOutput.format(_a) : "a6p");
  var b = (machineConfiguration.isMachineCoordinate(1) ? aOutput.format(_b) : "b6p");
  var c = (machineConfiguration.isMachineCoordinate(2) ? aOutput.format(_c) : "c6p");

  if (x || y || z || a || b || c) {
    writeBlock(getFeed(feed));
    writeBlock("Axyzabc 0, " + x + ", " + y + ", " + z + ", " + a + ", " + b + ", " + c + ";");
  } else if (f) {
    if (getNextRecord().isMotion()) { // try not to output feed without motion
      forceFeed(); // force feed on next line
    } else {
      writeBlock(getFeed(feed));
    }
  }
}

function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {
  var f = getFeed(feed);
  if (isHelical() || (getCircularPlane() != PLANE_XY)) {
    var t = tolerance;
    if (hasParameter("operation:tolerance")) {
      t = getParameter("operation:tolerance");
    }
    linearize(t);
    return;
  }

  var start = getCurrentPosition();
  var startAngle = Math.atan2(start.y - cy, start.x - cx);
  var endAngle = Math.atan2(y - cy, x - cx);

  if (f) {
    writeBlock(f);
  }

  writeln(
    translate("Circle")  + " " +
    xyzFormat.format(2 * getCircularRadius()) + ", " +
    "0, " + // hs
    "0, " + // hl
    (clockwise ? -360 : 0) + ", " +
    angleFormat.format(startAngle) + ", " + // begin angle
    angleFormat.format(endAngle) + ", " + // end angle
    "0, " + // do not connect start/end
    "0, " + // center
    "2, " + // fk
    "1, " + // yf
    xyzFormat.format(getHelicalPitch()) + ";" // zb
  );
}

function translate(text) {
  switch (language) {
  case "en":
    return text;
  case "de":
    switch (text) {
    case "Coolant":
      return "Sprueh";
    case "Condition":
      return "Bedingung";
    case "Submacro":
      return "Submakro";
    case "Dynamics":
      return "Dynamik";
    case "Contour_smoothing":
      return "Konturglaettung";
    case "Label":
      return "Markierung";
    case "Tcomp":
      return "Fkomp";
    case "Message":
      return "Melde";
    case "Feed":
      return "Vorschub";
    case "Rpm":
      return "Drehzahl";
    case "Number of tools in use":
      return "Anzahl der benutzten Werkzeuge";
    case "Tool":
      return "Werkzeug";
    case "Drill":
      return "Bohren";
    case "Circle":
      return "Kreis";
    case "Thread":
      return "Gewinde";
    case "Setzp":
      return "Setrel";
    case "Workpiece dimensions":
      return "Abmessungen Werkstueck";
    case "Zeromem":
      return "Relsp";
    case "Description":
      return "Beschreibung";
    case "Part size":
      return "Groesse";
    case "Zheight":
      return "Zhmess";
    case "Rotation":
      return "Drehung";
    case "ToolRetraction":
      return "Wzrueckzug";
    case "Shift":
      return "Verschieben";
    case "Tilt":
      return "Schwenken";
    case "\r\n________________________________________" +
         "\r\n|              error                    |" +
         "\r\n|                                       |" +
         "\r\n| 4/5 axis operations detected.         |" +
         "\r\n| You have to enable the property       |" +
         "\r\n| got4thAxis or got5Axis,               |" +
         "\r\n| otherwise you can only post           |" +
         "\r\n| 3 Axis programs.                      |" +
         "\r\n| If you still have issues,             |" +
         "\r\n| please contact www.DATRON.com!        |" +
         "\r\n|_______________________________________|\r\n":
      return "\r\n________________________________________" +
        "\r\n|              Fehler                    |" +
        "\r\n|                                        |" +
        "\r\n| 4/5 Achs Operationen gefunden.         |" +
        "\r\n| Sie muessen die Property               |" +
        "\r\n| got4thAxis bzw. got5thAxis aktivieren, |" +
        "\r\n| andernfalls koennen Sie lediglich      |" +
        "\r\n| 3 Achsen Programme erzeugen.           |" +
        "\r\n| Besteht das Problem weiterhin,         |" +
        "\r\n| wenden Sie sich bitte an www.datron.de |" +
        "\r\n|________________________________________|\r\n";
    }
    break; // end of German
  }
  return text; // use English
}

var currentCoolantMode = COOLANT_OFF;
var coolantOff = undefined;

function setCoolant(coolant) {
  var coolantCodes = getCoolantCodes(coolant);
  if (Array.isArray(coolantCodes)) {
    for (var c in coolantCodes) {
      writeBlock(translate("Coolant") + " 4, 0" + ", " + coolantCodes[c] + ", 0;");
    }
    return undefined;
  }
  return coolantCodes;
}

function getCoolantCodes(coolant) {
  var multipleCoolantBlocks = new Array(); // create a formatted array to be passed into the outputted line
  if ((getProperty("useCoolant") != undefined) && !getProperty("useCoolant")) {
    return undefined;
  }
  if (!coolants) {
    error(localize("Coolants have not been defined."));
  }
  if (tool.type == TOOL_PROBE) { // avoid coolant output for probing
    coolant = COOLANT_OFF;
  }
  if (coolant == currentCoolantMode) {
    return undefined; // coolant is already active
  }
  if ((coolant != COOLANT_OFF) && (currentCoolantMode != COOLANT_OFF) && (coolantOff != undefined)) {
    if (Array.isArray(coolantOff)) {
      for (var i in coolantOff) {
        multipleCoolantBlocks.push(coolantOff[i]);
      }
    } else {
      multipleCoolantBlocks.push(coolantOff);
    }
  }

  var m;
  var coolantCodes = {};
  for (var c in coolants) { // find required coolant codes into the coolants array
    if (coolants[c].id == coolant) {
      coolantCodes.on = coolants[c].on;
      if (coolants[c].off != undefined) {
        coolantCodes.off = coolants[c].off;
        break;
      } else {
        for (var i in coolants) {
          if (coolants[i].id == COOLANT_OFF) {
            coolantCodes.off = coolants[i].off;
            break;
          }
        }
      }
    }
  }
  if (coolant == COOLANT_OFF) {
    m = !coolantOff ? coolantCodes.off : coolantOff; // use the default coolant off command when an 'off' value is not specified
  } else {
    coolantOff = coolantCodes.off;
    m = coolantCodes.on;
  }

  if (!m) {
    onUnsupportedCoolant(coolant);
    m = 9;
  } else {
    if (Array.isArray(m)) {
      for (var i in m) {
        multipleCoolantBlocks.push(m[i]);
      }
    } else {
      multipleCoolantBlocks.push(m);
    }
    currentCoolantMode = coolant;
    return multipleCoolantBlocks; // return the single formatted coolant value
  }
  return undefined;
}

var mapCommand = {
};

function onCommand(command) {
  switch (command) {
  case COMMAND_COOLANT_OFF:
    setCoolant(COOLANT_OFF);
    return;
  case COMMAND_COOLANT_ON:
    return;
  case COMMAND_STOP:
    return;
  case COMMAND_START_SPINDLE:
    return;
  case COMMAND_LOCK_MULTI_AXIS:
    return;
  case COMMAND_UNLOCK_MULTI_AXIS:
    return;
  case COMMAND_START_CHIP_TRANSPORT:
    return;
  case COMMAND_STOP_CHIP_TRANSPORT:
    return;
  case COMMAND_BREAK_CONTROL:
    return;
  case COMMAND_TOOL_MEASURE:
    return;
  }

  var stringId = getCommandStringId(command);
  var mcode = mapCommand[stringId];
  if (mcode != undefined) {
    writeBlock(mFormat.format(mcode));
  } else {
    onUnsupportedCommand(command);
  }
}

function onSectionEnd() {
  if (currentSection.isMultiAxis() && (currentSection.getOptimizedTCPMode() == 0)) {
    writeBlock("Rtcp 0;");
  }

  // the code below gets the machine angles from previous operation.  closestABC must also be set to true
  if (currentSection.isMultiAxis() && currentSection.isOptimizedForMachine()) {
    currentMachineABC = currentSection.getFinalToolAxisABC();
  }

  if (((getCurrentSectionId() + 1) >= getNumberOfSections()) ||
      (tool.number != getNextSection().getTool().number)) {
    onCommand(COMMAND_BREAK_CONTROL);
  }
  if (isProbeOperation(currentSection)) {
    writeBlock(translate("Rpm") + " 1, 30, 0, 30;");
  }

  writeBlock(translate("ToolRetraction") + ";"); // optional
  setWorkPlane(new Vector(0, 0, 0), false); // optional
  forceWorkPlane(); // optional

  if (!isLastSection() && getProperty("showOperationDialog")) {
    writeBlock("$Message = \"Start next Operation\";");
    writeBlock(translate("Condition") + " optional_stop, 0, 1, 0, 9999;");
    writeBlock(translate("Message") + " $Message, 0, 0, 0;");
    writeBlock("$Message = \"OK\";");
  }
  writeBlock(") " + formatVariable("Sm_" + formatVariable(getOperationDescription(currentSection))) + ";");
  forceAny();
}

/** Output block to do safe retract and/or move to home position. */
function writeRetract() {
  if (arguments.length == 0) {
    error(localize("No axis specified for writeRetract()."));
    return;
  }
  var words = []; // store all retracted axes in an array
  for (var i = 0; i < arguments.length; ++i) {
    let instances = 0; // checks for duplicate retract calls
    for (var j = 0; j < arguments.length; ++j) {
      if (arguments[i] == arguments[j]) {
        ++instances;
      }
    }
    if (instances > 1) { // error if there are multiple retract calls for the same axis
      error(localize("Cannot retract the same axis twice in one line"));
      return;
    }
    switch (arguments[i]) {
    case X:
      words.push("X" + xyzFormat.format(machineConfiguration.hasHomePositionX() ? machineConfiguration.getHomePositionX() : 0));
      break;
    case Y:
      words.push("Y" + xyzFormat.format(machineConfiguration.hasHomePositionY() ? machineConfiguration.getHomePositionY() : 0));
      break;
    case Z:
      writeBlock(translate("ToolRetraction") + ";");
      retracted = true; // specifies that the tool has been retracted to the safe plane
      zOutput.reset();
      break;
    default:
      error(localize("Bad axis specified for writeRetract()."));
      return;
    }
  }
  if (words.length > 0) {
    writeBlock("Clamping_position");
  }
}

function onClose() {
  writeln("");

  if (getProperty("writeVersion")) {
    if ((typeof getHeaderVersion == "function") && getHeaderVersion()) {
      writeComment(localize("post version") + ": " + getHeaderVersion());
    }
    if ((typeof getHeaderDate == "function") && getHeaderDate()) {
      writeComment(localize("post modified") + ": " + getHeaderDate());
    }
  }

  // dump machine configuration
  var vendor = machineConfiguration.getVendor();
  var model = machineConfiguration.getModel();
  var description = machineConfiguration.getDescription();

  writeComment("Please make sure that the language on your control is set to " + "\"" + language + "\"");
  if (getProperty("writeMachine") && (vendor || model || description)) {
    writeComment(localize("Machine"));
    if (vendor) {
      writeComment("  " + localize("vendor") + ": " + vendor);
    }
    if (model) {
      writeComment("  " + localize("model") + ": " + model);
    }
    if (description) {
      writeComment("  " + localize("description") + ": "  + description);
    }
  }
  writeToolTable();

  // write jump to start operation
  if (getProperty("showOperationDialog")) {
    writeBlock(translate("Condition") + " 0, 0, 0 , startOperation, startOperation;");
  }

  writeMainProgram();
  writeComment("###############################################");

  writeRetract(Z);

  // setWorkPlane(new Vector(0, 0, 0), false); // reset working plane
  writeRetract(X, Y);
  zOutput.reset();
}

function setProperty(property, value) {
  properties[property].current = value;
}
