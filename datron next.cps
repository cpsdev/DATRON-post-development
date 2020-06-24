/**
  Copyright (C) 2012-2018 by Autodesk, Inc.
  All rights reserved.

  DATRON post processor configuration.

  $Revision$
  $Date$

  FORKID {21ADEFBF-939E-4D3F-A935-4E61F5958698}
*/

description = "DATRON next";
vendor = "DATRON";
vendorUrl = "http://www.datron.com";
legal = "Copyright (C) 2012-2018 by Autodesk, Inc.";
certificationLevel = 2;
minimumRevision = 40783;

longDescription = "Post for Datron next control. This post is for use with the Datron neo CNC.";

extension = "simpl";
setCodePage("utf-8");

capabilities = CAPABILITY_MILLING;
tolerance = spatial(0.002, MM);

minimumChordLength = spatial(0.25, MM);
minimumCircularRadius = spatial(0.01, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.01);
maximumCircularSweep = toRad(120);
allowHelicalMoves = true;
allowedCircularPlanes = (1 << PLANE_XY); // allow XY plane only

// user-defined properties
properties = {
  writeMachine : true, // write machine
  showNotes : false, // specifies that operation notes should be output
  useSmoothing : true, // specifies if smoothing should be used or not
  useDynamic : true, // specifies using dynamic mode or not
  machineType : "NEO", // specifiees the DATRON machine type
  useParkPosition : true, // specifies to use park position at the end of the program
  writeToolTable : true, // write the table with the geometric tool informations
  useSequences : true, // this use a sequence in the output format to perform on large files
  useExternalSequencesFiles : false, // this property create one external sequence files for each operation
  writeCoolantCommands : true, // disable the coolant commands in the file
  useParametricFeed : true, // specifies that feed should be output using parameters
  waitAfterOperation : false, // optional stop
  rotationAxisSetup : "none", // define the rotatry axis setup for the machine
  useSuction: false, // activate suction support
  createThreadChamfer: false, // create a chamfer with the thread milling tool
  preloadTool : false, //prepare a Tool for the DATROn tool assist
  writePathOffset : true, //write the definition for the PathOffset variable for every Operation
  useZAxisOffset : false,
  useRtcp : false  // use the NEXT feature RTCP for multiaxis operations
};
 
// user-defined property definitions
propertyDefinitions = {
  writeMachine: {title:"Write machine", description:"Output the machine settings in the header of the code.", group:0, type:"boolean"},
  showNotes: {title:"Show notes", description:"Writes operation notes as comments in the outputted code.", type:"boolean"},
  useSmoothing: {title:"Use smoothing", description:"Specifies if smoothing should be used or not.", type:"boolean"},
  useDynamic: {title:"Dynamic mode", description:"Specifies the using of dynamic mode or not.", type:"boolean"},
  machineType:{title:"Machine type",
    description:"Specifies the DATRON machine type.",
    type:"enum",
    values:[
      {title:"NEO", id:"NEO"},
      {title:"MX Cube", id:"MX"},
      {title:"Cube", id:"Cube"}
    ]},
  useParkPosition: {title: "Park at end of program", description:"Enable to use the park position at end of program.", type:"boolean"},
  writeToolTable: {title:"Write tool table", description:"Write a tool table containing geometric tool information.", group:0, type:"boolean"},
  useSequences: {title:"Use sequences", description:"If enables, sequences are used in the output format on large files.", type:"boolean"},
  useExternalSequencesFiles: {title:"Use external sequence files", description:"If enabled, an external sequence file is created for each operation.", type:"boolean"},
  writeCoolantCommands: {title:"Write coolant commands", description:"Enable/disable coolant code outputs for the entire program.", type:"boolean"},
  useParametricFeed:  {title:"Parametric feed", description:"Specifies the feed value that should be output using a Q value.", type:"boolean"},
  waitAfterOperation: {title:"Wait after operation", description:"If enabled, an optional stop is outputted to pause after each operation.", type:"boolean"},
  rotationAxisSetup : {title:"Setup rotary axis",
    description:"define if the machine is setup with additional rotary axis.",
    type:"enum",
    values:[
      {title:"No rotary axis", id:"NONE"},
      {title:"4th axis along X+", id:"4th"},
      {title:"DST (4th & 5th axis)", id:"DST"}
    ]},
  useSuction: {title:"Use Suction", description:"Enable the suction for every operation.", type:"boolean"},
  createThreadChamfer: {title:"Create a Thread Chamfer", description:"create a chamfer with the thread milling tool", type:"boolean"},
  preloadTool:{title:"Preload the next Tool", description:"Preload the next Tool in the DATRON Tool assist.", type: "boolean"},
  writePathOffset:{title:"Write Path Offset", description:"Write the PathOffset declaration.", type: "boolean"},
  useZAxisOffset:{title:"Output Z Offset command", description:"This creates a command to allow a manual Z offset for each operation.", type:"boolean"},
  useRtcp:{title:"Use RTCP", description:"Use the NEXT 5axis setup correction.", type:"boolean"}
};

var gFormat = createFormat({prefix:"G", width:2, zeropad:true, decimals:1});
var mFormat = createFormat({prefix:"M", width:2, zeropad:true, decimals:1});

var xyzFormat = createFormat({decimals:(unit == MM ? 5 : 5), forceDecimal:false});
var abcFormat = createFormat({decimals:5, scale:DEG});
var feedFormat = createFormat({decimals:(unit == MM ? 2 : 2)});
var toolFormat = createFormat({decimals:0});
var dimensionFormat = createFormat({decimals:(unit == MM ? 3 : 5), forceDecimal:false});
var rpmFormat = createFormat({decimals:0, scale:1});
var sleepFormat = createFormat({decimals:0, scale:1000}); // milliseconds
var workpieceFormat = createFormat({decimals:(unit == MM ? 3 : 4), forceSign:true, trim:false});

var toolOutput = createVariable({prefix:"Tool_", force:true}, toolFormat);
var feedOutput = createVariable({prefix:""}, feedFormat);

var xOutput = createVariable({prefix:" X="}, xyzFormat);
var yOutput = createVariable({prefix:" Y="}, xyzFormat);
var zOutput = createVariable({prefix:" Z="}, xyzFormat);
var aOutput = createVariable({prefix:" A="}, abcFormat);
var bOutput = createVariable({prefix:" B="}, abcFormat);
var cOutput = createVariable({prefix:" C="}, abcFormat);

var iOutput = createVariable({prefix:" dX=", force : true}, xyzFormat);
var jOutput = createVariable({prefix:" dY=", force : true}, xyzFormat);
var kOutput = createVariable({prefix:" dZ="}, xyzFormat);

// fixed settings
var useDatronFeedCommand = false; // unsupported for now, keep false
var language = "de"; // specifies the language, replace with getLangId()
var spacingDepth = 0;
var spacingString = "  ";
var spacing = "##########################################################";

// buffer for building up a program not serial created
var sequenceBuffer = new StringBuffer();

function NewOperation(operationCall) {
  this.operationCall = operationCall;
  this.operationProgram = new StringBuffer();
  this.operationProgram.append("");
}
var currentOperation;
function NewSimPLProgram() {
  this.moduleName = new StringBuffer();
  this.measuringSystem = "Metric";
  this.toolDescriptionList = new Array();
  this.workpieceGeometry = "";
  this.sequenceList = new Array();
  this.usingList = new Array();
  this.externalUsermodules = new Array();
  this.globalVariableList = new Array();
  this.mainProgram = new StringBuffer();
  this.operationList = new Array();
}

var SimPLProgram = new NewSimPLProgram();

// collected state
var currentFeedValue = -1;
var optionalSection = false;
var activeMovements; // do not use by default
var currentFeedId;

// format date + time
var timeFormat = createFormat({decimals:0, width:2, zeropad:true});
var now = new Date();
var nowDay = now.getDate();
var nowMonth = now.getMonth() + 1;
var nowHour = now.getHours();
var nowMin = now.getMinutes();
var nowSec = now.getSeconds();

function getSequenceName(section) {
  var sequenceName = "";
  if (properties.useExternalSequencesFiles) {
    sequenceName += FileSystem.getFilename(getOutputPath().substr(0, getOutputPath().lastIndexOf("."))) + "_";
  }
  sequenceName += "SEQUENCE_" + mapComment(getOperationDescription(section));
  return sequenceName;
}

function getFilename() {
  var filePath = getOutputPath();
  var filename = filePath.slice(filePath.lastIndexOf("\\") + 1, filePath.lastIndexOf("."));
  return filename;
}

function getOperationName(section) {
  return "Operation_" + getOperationDescription(section);
}

function capitalizeFirstLetter(text) {
  return text.substring(0, 1).toUpperCase() + text.substring(1).toLowerCase();
}

function getSpacing() {
  var space = "";
  for (var i = 0; i < spacingDepth; i++) {
    space += spacingString;
  }
  return space;
}

/**
  Redirect the output to an infinite number of buffers ;-)
  works like a stack you can use many redirection levels and go back again
*/
var writeRedirectionStack = new Array();

function setWriteRedirection(redirectionbuffer) {
  writeRedirectionStack.push(redirectionbuffer);
}

function resetWriteRedirection() {
  return writeRedirectionStack.pop();
}

/**
  Writes the specified block.
*/
function writeBlock() {
  var text = getSpacing() + formatWords(arguments);
  if (writeRedirectionStack.length == 0) {
    writeWords(text);
  } else {
    writeRedirectionStack[writeRedirectionStack.length - 1].append(text + "\r\n");
  }
}

/**
  Output a comment.
*/
function writeComment(text) {
  if (text) {
    text = getSpacing() + "# " + text;
    if (writeRedirectionStack.length == 0) {
      writeln(text);
    } else {
      writeRedirectionStack[writeRedirectionStack.length - 1].append(text + "\r\n");
    }
  }
}

var charMap = {
  "\u00c4" : "Ae",
  "\u00e4" : "ae",
  "\u00dc" : "Ue",
  "\u00fc" : "ue",
  "\u00d6" : "Oe",
  "\u00f6" : "oe",
  "\u00df" : "ss",
  "\u002d" : "_",
  "\u0020" : "_"
};

/** Map specific chars. */
function mapComment(text) {
  text = formatVariable(text);
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
  return String(text).replace(/[^A-Za-z0-9\-_]/g, "");
}

function onOpen() {
  // note: setup your machine here
  if (properties.rotationAxisSetup == "4th") {
    var aAxis = createAxis({coordinate:0, table:true, axis:[1, 0, 0], range:[0, 360], cyclic:true, preference:0});
    machineConfiguration = new MachineConfiguration(aAxis);
    machineConfiguration.setVendor("DATRON");
    machineConfiguration.setModel("NEO with A Axis");
    machineConfiguration.setDescription("DATRON NEXT Control with additional A-Axis");
    setMachineConfiguration(machineConfiguration);
    optimizeMachineAngles2(1); // TCP mode 0:Full TCP 1: Map Tool Tip to Axis
  }

  // note: setup your machine here
  if (properties.rotationAxisSetup == "DST") {
    var aAxis = createAxis({coordinate:0, table:true, axis:[1, 0, 0], range:[-10, 110], cyclic:false, preference:0});
    var cAxis = createAxis({coordinate:2, table:true, axis:[0, 0, 1], range:[-360, 360], cyclic:true, preference:0});
    machineConfiguration = new MachineConfiguration(aAxis, cAxis);
    machineConfiguration.setVendor("DATRON");
    machineConfiguration.setModel("NEXT with DST");
    machineConfiguration.setDescription("DATRON NEXT Control with additional DST");
    setMachineConfiguration(machineConfiguration);
    optimizeMachineAngles2(1); // TCP mode 0:Full TCP 1: Map Tool Tip to Axis
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

  // header of the main program
  writeProgramHeader();
  spacingDepth -= 1;
  resetWriteRedirection();

  //Probing Surface Inspection
  if (typeof inspectionWriteVariables == "function") {
    inspectionWriteVariables();
  }
  // the rest of program main will be set at closing when all the code is analysed
}

function getOperationDescription(section) {
  // creates the name of the operation
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
  var description = operationComment + "_" + cycleTypeString + "_" + sectionID;
  return description;
}

function createToolVariables() {
  var tools = getToolTable();
  var toolVariables = new Array();
  if (tools.getNumberOfTools() > 0 && !properties.writeToolTable) {
    for (var i = 0; i < tools.getNumberOfTools(); ++i) {
      var tool = tools.getTool(i);
      toolVariables.push(toolOutput.format(tool.number) + ":number");
    }
  }
  return toolVariables;
}

function getNextTool(number) {
  var currentSectionId = getCurrentSectionId();
  if (currentSectionId < 0) {
    return null;
  }
  for (var i = currentSectionId + 1; i < getNumberOfSections(); ++i) {
    var section = getSection(i);
    var sectionTool = section.getTool();
    if (number != sectionTool.number) {
      return sectionTool; // found next tool
    }
  }
  return null; // not found
}

function createToolDescriptionTable() {
  if (!properties.writeToolTable) {
    return new Array();
  }
  
  var toolDescriptionArray = new Array();
  var toolNameList = new Array();
  var numberOfSections = getNumberOfSections();
  for (var i = 0; i < numberOfSections; ++i) {
    var section = getSection(i);
    var tool = section.getTool();
    if (tool.type != TOOL_PROBE) {
      var toolName = createToolName(tool);
      var toolProgrammed = createToolDescription(tool);
      if (toolNameList.indexOf(toolName) == -1) {
        toolNameList.push(toolName);
        toolDescriptionArray.push(toolProgrammed);
      } else {
        /*
       if (toolDescriptionArray.indexOf(toolProgrammed) == -1) {
         error("\r\n#####################################\r\nOne ore more tools have the same name!\r\nPlease change the tool number to make the name unique.\r\n" + toolDescriptionArray.join("\r\n") + "\r\n\r\n" +
         toolNameList.join("\r\n") + "#####################################\r\n");
       }
*/
      }
    }
  }

  return toolDescriptionArray;
}

function createToolDescription(tool) {
  var toolProgrammed = "@ ToolDescription : " +
      "\"" + "Name" + "\"" + ":" +  "\"" + createToolName(tool) + "\"" + ", " +
      "\"" + "Category" + "\"" + ":" +  "\"" + translateToolType(tool.type) + "\"" + ", " +
      "\"" + "ArticleNr" + "\"" + ":" +  "\"" + tool.productId + "\"" + ", " +
      "\"" + "ToolNumber" + "\"" + ":" + toolFormat.format(tool.number) + ", " +
      "\"" + "Vendor" + "\"" + ":" +  "\"" + tool.vendor + "\"" + ", " +
      "\"" + "Diameter" + "\"" + ":" + dimensionFormat.format(tool.diameter) + ", " +
      "\"" + "TipAngle" + "\"" + ":" + dimensionFormat.format(toDeg(tool.taperAngle)) + ", " +
      "\"" + "TipDiameter" + "\"" + ":" + dimensionFormat.format(tool.tipDiameter) + ", " +
      "\"" + "FluteLength" + "\"" + ":" + dimensionFormat.format(tool.fluteLength) + ", " +
      "\"" + "CornerRadius" + "\"" + ":" + dimensionFormat.format(tool.cornerRadius) + ", " +
      "\"" + "ShoulderLength" + "\"" + ":" + dimensionFormat.format(tool.shoulderLength) + ", " +
      "\"" + "ShoulderDiameter" + "\"" + ":" + dimensionFormat.format(tool.diameter) + ", " +
      "\"" + "BodyLength" + "\"" + ":" + dimensionFormat.format(tool.bodyLength) + ", " +
      "\"" + "NumberOfFlutes" + "\"" + ":" + toolFormat.format(tool.numberOfFlutes) + ", " +
      "\"" + "ThreadPitch" + "\"" + ":" + dimensionFormat.format(tool.threadPitch) + ", " +
      "\"" + "ShaftDiameter" + "\"" + ":" + dimensionFormat.format(tool.shaftDiameter) + ", " +
      "\"" + "OverallLength" + "\"" + ":" + dimensionFormat.format(tool.bodyLength + 2 * tool.shaftDiameter) +
      " @";
  return toolProgrammed;
}

/**
  Generate the logical tool name for the assignment table of used tools.
*/
function createToolName(tool) {
  var toolName = toolFormat.format(tool.number);
  toolName += "_" + translateToolType(tool.type);
  if (tool.comment) {
    toolName += "_" + tool.comment;
  }
  if (tool.diameter) {
    toolName += "_D" + tool.diameter;
  }
  var description = tool.getDescription();
  if (description) {
    toolName += "_" + description;
  }
  toolName = formatVariable(toolName);
  return toolName;
}

/**
  Translate HSM tools to Datron tool categories.
*/
function translateToolType(toolType) {

  var datronCategoryName = "";

  toolCategory = toolType;
  switch (toolType) {
  case TOOL_UNSPECIFIED:
    datronCategoryName = "Unspecified";
    break;
  case TOOL_DRILL:
    datronCategoryName = "Drill";
    break;
  case TOOL_DRILL_CENTER:
    datronCategoryName = "DrillCenter";
    break;
  case TOOL_DRILL_SPOT:
    datronCategoryName = "DrillSpot";
    break;
  case TOOL_DRILL_BLOCK:
    datronCategoryName = "DrillBlock";
    break;
  case TOOL_MILLING_END_FLAT:
    datronCategoryName = "MillingEndFlat";
    break;
  case TOOL_MILLING_END_BALL:
    datronCategoryName = "MillingEndBall";
    break;
  case TOOL_MILLING_END_BULLNOSE:
    datronCategoryName = "MillingEndBullnose";
    break;
  case TOOL_MILLING_CHAMFER:
    datronCategoryName = "Graver";
    break;
  case TOOL_MILLING_FACE:
    datronCategoryName = "MillingFace";
    break;
  case TOOL_MILLING_SLOT:
    datronCategoryName = "MillingSlot";
    break;
  case TOOL_MILLING_RADIUS:
    datronCategoryName = "MillingRadius";
    break;
  case TOOL_MILLING_DOVETAIL:
    datronCategoryName = "MillingDovetail";
    break;
  case TOOL_MILLING_TAPERED:
    datronCategoryName = "MillingTapered";
    break;
  case TOOL_MILLING_LOLLIPOP:
    datronCategoryName = "MillingLollipop";
    break;
  case TOOL_TAP_RIGHT_HAND:
    datronCategoryName = "TapRightHand";
    break;
  case TOOL_TAP_LEFT_HAND:
    datronCategoryName = "TapLeftHand";
    break;
  case TOOL_REAMER:
    datronCategoryName = "Reamer";
    break;
  case TOOL_BORING_BAR:
    datronCategoryName = "BoringBar";
    break;
  case TOOL_COUNTER_BORE:
    datronCategoryName = "CounterBore";
    break;
  case TOOL_COUNTER_SINK:
    datronCategoryName = "CounterSink";
    break;
  case TOOL_HOLDER_ONLY:
    datronCategoryName = "HolderOnly";
    break;
  case TOOL_PROBE:
    datronCategoryName = "XYZSensor";
    break;
  default:
    datronCategoryName = "Unspecified";
  }
  return datronCategoryName;
}

function writeProgramHeader() {
  // write creation Date
  var date = timeFormat.format(nowDay) + "." + timeFormat.format(nowMonth) + "." + now.getFullYear();
  var time = timeFormat.format(nowHour) + ":" + timeFormat.format(nowMin);
  setWriteRedirection(SimPLProgram.moduleName);
  writeComment("!File ; generated at " + date + " - " + time);
  if (programComment) {
    writeComment(formatComment(programComment));
  }

  writeBlock(" ");
  // dump machine configuration
  var vendor = machineConfiguration.getVendor();
  var model = machineConfiguration.getModel();
  var description = machineConfiguration.getDescription();

  if (properties.writeMachine && (vendor || model || description)) {
    writeComment(localize("Machine"));
    if (vendor) {
      writeComment("  " + localize("vendor") + ": " + vendor);
    }
    if (model) {
      writeComment("  " + localize("model") + ": " + model);
    }
    if (description) {
      writeComment("  " + localize("description") + ": " + description);
    }
  }

  writeBlock("module " + "CamGeneratedModule");
  writeBlock(" ");

  writeBlock("@ MeasuringSystem = " + (unit == MM ? "\"" + "Metric" + "\"" + " @" : "\"" + "Imperial" + "\"" + " @"));
  resetWriteRedirection();

  // set the table of used tools in the header of the program
  SimPLProgram.toolDescriptionList =  createToolDescriptionTable();

  // set the workpiece information
  // TODO anapssen das es wieder geposted wird
  SimPLProgram.workpieceGeometry = writeWorkpiece();
  // set the sequence header in the program file
  if (properties.useSequences) {
    var sequences = new Array();
    var numberOfSections = getNumberOfSections();
    for (var i = 0; i < numberOfSections; ++i) {
      var section = getSection(i);
      if (!isProbeOperation(section)) {
        sequences.push("sequence " + getSequenceName(section));
      }
    }
    if (properties.useExternalSequencesFiles) {
      writeBlock("@ EmbeddedSequences = false @");
    }

    SimPLProgram.sequenceList = sequences;
  }

  // set usings
  SimPLProgram.usingList.push("using Base");
  if (properties.rotationAxisSetup != "NONE") {
    SimPLProgram.usingList.push("using Rtcp");
  }
  if (properties.waitAfterOperation) {
    SimPLProgram.usingList.push("import System");
  }

  addInspectionReferences();
 
  // set paramtric feed variables
  //var feedDeclaration = new Array();
  var currentMovements = new Array();
  var numberOfSections = getNumberOfSections();
  for (var i = 0; i < numberOfSections; ++i) {
    var section = getSection(i);
    if (properties.useParametricFeed && (!useDatronFeedCommand)) {
      activeFeeds = initializeActiveFeeds(section);
      for (var j = 0; j < activeFeeds.length; ++j) {
        var feedContext = activeFeeds[j];
        var feedDescription = formatVariable(feedContext.description);
        if (SimPLProgram.globalVariableList.indexOf(feedDescription + ":number") == -1) {
          SimPLProgram.globalVariableList.push(feedDescription + ":number");
        }
      }
    }
  }

  // if (!useDatronFeedCommand) {
  //   if (feedDeclaration != 0) {
  //     SimPLProgram.globalVariableList.push(feedDeclaration);
  //   }
  // }
  setWriteRedirection(SimPLProgram.mainProgram);
  writeBlock("export program Main # " + (programName ? (SP + formatComment(programName)) : "") + ((unit == MM) ? " MM" : " INCH"));
  spacingDepth += 1;
  writeBlock("Absolute");

  // ste the multiaxis mode
  if (properties.rotationAxisSetup != "NONE" && properties.useRtcp) {
    writeBlock("MultiAxisMode On");
  }
  
  // set the parameter tool table
  SimPLProgram.globalVariableList.push(createToolVariables());

  if (!properties.writeToolTable) {
    var tools = getToolTable();
    writeComment("Number of tools in use" + ": " + tools.getNumberOfTools());
    if (tools.getNumberOfTools() > 0) {
      for (var i = 0; i < tools.getNumberOfTools(); ++i) {
        var tool = tools.getTool(i);
        var toolAsigment = toolOutput.format(tool.number) + " = " + (tool.number) + "# " +
          formatComment(getToolTypeName(tool.type)) + " " +
          "D:" + dimensionFormat.format(tool.diameter) + " " +
          "L2:" + dimensionFormat.format(tool.fluteLength) + " " +
          "L3:" + dimensionFormat.format(tool.shoulderLength) + " " +
          "ProductID:" + formatComment(tool.productId);
        writeBlock(toolAsigment);
      }
      writeBlock(" ");
    }
  }
  resetWriteRedirection();
}

function writeWorkpiece() {
  var workpieceString = new StringBuffer();
  setWriteRedirection(workpieceString);
  var workpiece = getWorkpiece();
  var delta = Vector.diff(workpiece.upper, workpiece.lower);

  writeBlock("# Workpiece dimensions");
  writeBlock(
    "# min:      X: " + workpieceFormat.format(workpiece.lower.x) + ";" +
    " Y: " + workpieceFormat.format(workpiece.lower.y) + ";" +
    " Z: " + workpieceFormat.format(workpiece.lower.z));
  writeBlock(
    "# max:      X: " + workpieceFormat.format(workpiece.upper.x) + ";" +
    " Y: " + workpieceFormat.format(workpiece.upper.y) + ";" +
    " Z: " + workpieceFormat.format(workpiece.upper.z));
  writeBlock(
    "# Part size X: " + workpieceFormat.format(delta.x) + ";" +
    " Y: " + workpieceFormat.format(delta.y) + ";" +
    " Z: " + workpieceFormat.format(delta.z));

  writeBlock("@ WorkpieceGeometry : " + "\"" + "MinEdge" + "\"" + ":{" + "\"" + "X" + "\"" + ":" + workpieceFormat.format(workpiece.lower.x) + "," +
    "\"" + "Y" + "\"" + ":" + workpieceFormat.format(workpiece.lower.y) + "," +
    "\"" + "Z" + "\"" + ":" +  workpieceFormat.format(workpiece.lower.z) + "}," +
    "\"" + "MaxEdge" + "\"" + ":{" + "\"" + "X" + "\"" + ":" + workpieceFormat.format(workpiece.upper.x) + "," +
    "\"" + "Y" + "\"" + ":" + workpieceFormat.format(workpiece.upper.y) + "," +
    "\"" + "Z" + "\"" + ":" + workpieceFormat.format(workpiece.upper.z) + "}" +
    " @");
  resetWriteRedirection();
  return workpieceString;
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

function FeedContext(id, description, datronFeedName, feed) {
  this.id = id;
  this.description = description;
  this.datronFeedName = datronFeedName;
  if (revision < 41759) {
    this.feed = (unit == MM ? feed : toPreciseUnit(feed, MM)); // temporary solution
  } else {
    this.feed = feed;
  }
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
        if (useDatronFeedCommand) {
          return ("Feed " + capitalizeFirstLetter(feedContext.datronFeedName));
        } else {
          return ("Feed=" + formatVariable(feedContext.description));
        }
      }
    }
    currentFeedId = undefined; // force Q feed next time
  }
  if (feedFormat.areDifferent(currentFeedValue, f)) {
    currentFeedValue = f;
    return "Feed=" + feedFormat.format(f);
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
      var feedContext = new FeedContext(id, localize("Cutting"), "roughing", section.getParameter("operation:tool_feedCutting"));
      addFeedContext(feedContext, activeFeeds);
      activeMovements[MOVEMENT_CUTTING] = feedContext;
      activeMovements[MOVEMENT_LINK_TRANSITION] = feedContext;
      activeMovements[MOVEMENT_EXTENDED] = feedContext;
    }
    ++id;
    if (movements & (1 << MOVEMENT_PREDRILL)) {
      feedContext = new FeedContext(id, localize("Predrilling"), "plunge", section.getParameter("operation:tool_feedCutting"));
      activeMovements[MOVEMENT_PREDRILL] = feedContext;
      addFeedContext(feedContext, activeFeeds);
    }
    ++id;
    if (section.hasParameter("operation-strategy") && (section.getParameter("operation-strategy") == "drill")) {
      var feedContext = new FeedContext(id, localize("Cutting"), "roughing", section.getParameter("operation:tool_feedCutting"));
      addFeedContext(feedContext, activeFeeds);
      activeMovements[MOVEMENT_CUTTING] = feedContext;
    }
    ++id;
  }
  if (section.hasParameter("operation:finishFeedrate")) {
    if (movements & (1 << MOVEMENT_FINISH_CUTTING)) {
      var feedContext = new FeedContext(id, localize("Finish"), "finishing", section.getParameter("operation:finishFeedrate"));
      addFeedContext(feedContext, activeFeeds);
      activeMovements[MOVEMENT_FINISH_CUTTING] = feedContext;
    }
    ++id;
  } else if (section.hasParameter("operation:tool_feedCutting")) {
    if (movements & (1 << MOVEMENT_FINISH_CUTTING)) {
      var feedContext = new FeedContext(id, localize("Finish"), "finishing", section.getParameter("operation:tool_feedCutting"));
      addFeedContext(feedContext, activeFeeds);
      activeMovements[MOVEMENT_FINISH_CUTTING] = feedContext;
    }
    ++id;
  }
  if (section.hasParameter("operation:tool_feedEntry")) {
    if (movements & (1 << MOVEMENT_LEAD_IN)) {
      var feedContext = new FeedContext(id, localize("Entry"), "approach", section.getParameter("operation:tool_feedEntry"));
      addFeedContext(feedContext, activeFeeds);
      activeMovements[MOVEMENT_LEAD_IN] = feedContext;
    }
    ++id;
  }
  if (section.hasParameter("operation:tool_feedExit")) {
    if (movements & (1 << MOVEMENT_LEAD_OUT)) {
      var feedContext = new FeedContext(id, localize("Exit"), "approach", section.getParameter("operation:tool_feedExit"));
      addFeedContext(feedContext, activeFeeds);
      activeMovements[MOVEMENT_LEAD_OUT] = feedContext;
    }
    ++id;
  }
  if (section.hasParameter("operation:noEngagementFeedrate")) {
    if (movements & (1 << MOVEMENT_LINK_DIRECT)) {
      var feedContext = new FeedContext(id, localize("Direct"), "approach", section.getParameter("operation:noEngagementFeedrate"));
      addFeedContext(feedContext, activeFeeds);
      activeMovements[MOVEMENT_LINK_DIRECT] = feedContext;
    }
    ++id;
  } else if (section.hasParameter("operation:tool_feedCutting") &&
    section.hasParameter("operation:tool_feedEntry") &&
    section.hasParameter("operation:tool_feedExit")) {
    if (movements & (1 << MOVEMENT_LINK_DIRECT)) {
      var feedContext = new FeedContext(id, localize("Direct"), "approach", Math.max(section.getParameter("operation:tool_feedCutting"), section.getParameter("operation:tool_feedEntry"), section.getParameter("operation:tool_feedExit")));
      addFeedContext(feedContext, activeFeeds);
      activeMovements[MOVEMENT_LINK_DIRECT] = feedContext;
    }
    ++id;
  }
  if (section.hasParameter("operation:reducedFeedrate")) {
    if (movements & (1 << MOVEMENT_REDUCED)) {
      var feedContext = new FeedContext(id, localize("Reduced"), "finishing", section.getParameter("operation:reducedFeedrate"));
      addFeedContext(feedContext, activeFeeds);
      activeMovements[MOVEMENT_REDUCED] = feedContext;
    }
    ++id;
  }
  if (section.hasParameter("operation:tool_feedRamp")) {
    if (movements & ((1 << MOVEMENT_RAMP) | (1 << MOVEMENT_RAMP_HELIX) | (1 << MOVEMENT_RAMP_PROFILE) | (1 << MOVEMENT_RAMP_ZIG_ZAG))) {
      var feedContext = new FeedContext(id, localize("Ramping"), "ramp", section.getParameter("operation:tool_feedRamp"));
      addFeedContext(feedContext, activeFeeds);
      activeMovements[MOVEMENT_RAMP] = feedContext;
      activeMovements[MOVEMENT_RAMP_HELIX] = feedContext;
      activeMovements[MOVEMENT_RAMP_PROFILE] = feedContext;
      activeMovements[MOVEMENT_RAMP_ZIG_ZAG] = feedContext;
    }
    ++id;
  }
  if (section.hasParameter("operation:tool_feedPlunge")) {
    if (movements & (1 << MOVEMENT_PLUNGE)) {
      var feedContext = new FeedContext(id, localize("Plunge"), "plunge", section.getParameter("operation:tool_feedPlunge"));
      addFeedContext(feedContext, activeFeeds);
      activeMovements[MOVEMENT_PLUNGE] = feedContext;
    }
    ++id;
  }

  // this part allows us to use feedContext also for the cycles
  if (hasParameter("operation:cycleType")) {
    var cycleType = getParameter("operation:cycleType");
    if (hasParameter("movement:plunge")) {
      var feedContext = new FeedContext(id, localize("Plunge"), "plunge", section.getParameter("movement:plunge"));
      addFeedContext(feedContext, activeFeeds);
      ++id;
    }

    switch (cycleType) {
    case "thread-milling":
      if (hasParameter("movement:plunge")) {
        var feedContext = new FeedContext(id, localize("Plunge"), "plunge", section.getParameter("movement:plunge"));
        addFeedContext(feedContext, activeFeeds);
        ++id;
      }
      if (hasParameter("movement:ramp")) {
        var feedContext = new FeedContext(id, localize("Ramping"), "ramp", section.getParameter("movement:ramp"));
        addFeedContext(feedContext, activeFeeds);
        ++id;
      }
      if (hasParameter("movement:finish_cutting")) {
        var feedContext = new FeedContext(id, localize("Finish"), "finishing", section.getParameter("movement:finish_cutting"));
        addFeedContext(feedContext, activeFeeds);
        ++id;
      }
      break;
    case "bore-milling":
      if (section.hasParameter("movement:plunge")) {
        var feedContext = new FeedContext(id, localize("Plunge"), "plunge", section.getParameter("movement:plunge"));
        addFeedContext(feedContext, activeFeeds);
        ++id;
      }
      if (section.hasParameter("movement:ramp")) {
        var feedContext = new FeedContext(id, localize("Ramping"), "ramp", section.getParameter("movement:ramp"));
        addFeedContext(feedContext, activeFeeds);
        ++id;
      }
      if (hasParameter("movement:finish_cutting")) {
        var feedContext = new FeedContext(id, localize("Finish"), "finishing", section.getParameter("movement:finish_cutting"));
        addFeedContext(feedContext, activeFeeds);
        ++id;
      }
      break;
    }
  }

  if (true) { // high feed
    if (movements & (1 << MOVEMENT_HIGH_FEED)) {
      var feedContext = new FeedContext(id, localize("High Feed"), "roughing", this.highFeedrate);
      addFeedContext(feedContext, activeFeeds);
      activeMovements[MOVEMENT_HIGH_FEED] = feedContext;
    }
    ++id;
  }
  return activeFeeds;
}

/** Check that all elements are only one time in the result list. */
function addFeedContext(feedContext, activeFeeds) {
  if (activeFeeds.indexOf(feedContext) == -1) {
    activeFeeds.push(feedContext);
  }
}

var currentWorkPlaneABC = undefined;

function forceWorkPlane() {
  currentWorkPlaneABC = undefined;
}

function setWorkPlane(abc) {
  if (!machineConfiguration.isMultiAxisConfiguration()) {
    return; // ignore
  }
  if (isInspectionOperation(currentSection) && !is3D()) {
    error(localize("Multi axis Inspect surface is not supported."));
    return;
  }
  forceWorkPlane(); // always need the new workPlane
  forceABC();
  if ((properties.rotationAxisSetup != "NONE") && properties.useRtcp) {
    writeBlock("MoveToSafetyPosition");
  } else {
    writeBlock("MoveToSafetyPosition");
  }
  writeBlock("Rapid" + aOutput.format(abc.x) + bOutput.format(abc.y) + cOutput.format(abc.z));

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
      + conditional(machineConfiguration.isMachineCoordinate(2), " C" + abcFormat.format(abc.z)));
  }

  var direction = machineConfiguration.getDirection(abc);
  if (!isSameDirection(direction, W.forward)) {
    error(localize("Orientation not supported."));
  }

  if (!machineConfiguration.isABCSupported(abc)) {
    error(
      localize("Work plane is not supported") + ":"
      + conditional(machineConfiguration.isMachineCoordinate(0), " A" + abcFormat.format(abc.x))
      + conditional(machineConfiguration.isMachineCoordinate(1), " B" + abcFormat.format(abc.y))
      + conditional(machineConfiguration.isMachineCoordinate(2), " C" + abcFormat.format(abc.z)));
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

function onSection() {
  // this is the container that hold all operation informations...
  currentOperation = new NewOperation(getOperationName(currentSection));
  setWriteRedirection(currentOperation.operationProgram);

  var forceToolAndRetract = optionalSection && !currentSection.isOptional();
  optionalSection = currentSection.isOptional();
  var tool = currentSection.getTool();

  if (!isProbeOperation(currentSection) && hasParameter("operation:cycleTime")) {
    writeComment("Operation Time: " + formatCycleTime(currentSection.getCycleTime()));
  }

  var showToolZMin = true;
  if (showToolZMin) {
    if (is3D()) {
      var zRange = currentSection.getGlobalZRange();
      var number = tool.number;
      zRange.expandToRange(currentSection.getGlobalZRange());
      writeComment("ZMIN = " + xyzFormat.format(zRange.getMinimum()));
    }
  }

  // create sub program
  writeBlock("program " + getOperationName(currentSection));
  spacingDepth += 1;

  if (passThrough) {
    var joinString = "\r\n" + getSpacing();
    var passThroughString = passThrough.join(joinString);
    if (passThroughString != "") {
      writeBlock(passThroughString);
    }
    passThrough = [];
  }

  // this control structure allows us to show the user the operation from the CAM application as a block of within the whole program similarly to Heidenhain structure.
  writeBlock("BeginBlock name=" + "\"" + getOperationDescription(currentSection) + "\"");
  var operationTolerance = tolerance;
  if (hasParameter("operation:tolerance")) {
    if (operationTolerance < getParameter("operation:tolerance")) {
      operationTolerance = getParameter("operation:tolerance");
    }
  }

  //load the matching workOffset
  var workOffset = currentSection.getWorkOffset();
  if (workOffset != 0) {
    writeBlock("LoadWcs name=\"" + workOffset + "\"");
  }
  if (properties.useSmoothing && !currentSection.isMultiAxis() && !isProbeOperation(currentSection)) {
    writeBlock("Smoothing On allowedDeviation=" + xyzFormat.format(operationTolerance * 1.2));
  } else {
    writeBlock("Smoothing Off");
  }

  if (properties.useDynamic) {
    var dynamic = 5;
    operationName = getOperationName(currentSection).toUpperCase();
    dynamicIndex = operationName.lastIndexOf("DYN") + 3;
    expliciteDynamic = parseInt(operationName.substring(dynamicIndex, dynamicIndex + 1), 10);
    if ((!isNaN(expliciteDynamic)) && (expliciteDynamic > 0 && expliciteDynamic < 6)) {
      writeBlock("Dynamic = " + expliciteDynamic +  "  # Created from Operation Name");
      dynamic = expliciteDynamic;
    } else {
      // set machine type specific dynamic sets
      switch (properties.machineType) {
      case "NEO":
        dynamic = 5;
        break;
      case "MX":
      case "CUBE":
        if (operationTolerance <= (unit == MM ? 0.04 : (0.04 / 25.4))) {
          dynamic = 4;
        }
        if (operationTolerance <= (unit == MM ? 0.02 : (0.02 / 25.4))) {
          dynamic = 3;
        }
        if (operationTolerance <= (unit == MM ? 0.005 : (0.005 / 25.4))) {
          dynamic = 2;
        }
        if (operationTolerance <= (unit == MM ? 0.003 : (0.003 / 25.4))) {
          dynamic = 1;
        }
        break;
      }
      writeBlock("Dynamic = " + dynamic);
    }
  }

  if (properties.waitAfterOperation) {
    showWaitDialog(getOperationName(currentSection));
  }

  if (machineConfiguration.isMultiAxisConfiguration()) {
    if (currentSection.isMultiAxis()) {
      forceWorkPlane();
      cancelTransformation();
      var abc = currentSection.getInitialToolAxisABC();
      if ((properties.rotationAxisSetup != "NONE") && properties.useRtcp) {
        writeBlock("Rtcp On");
      }
      writeBlock("MoveToSafetyPosition");
      writeBlock("Rapid" + aOutput.format(abc.x) + bOutput.format(abc.y) + cOutput.format(abc.z));
    } else {
      forceWorkPlane();
      var abc = getWorkPlaneMachineABC(currentSection.workPlane);
      
      setWorkPlane(abc);
      if ((properties.rotationAxisSetup != "NONE") && properties.useRtcp) {
        writeBlock("Rtcp On");
      }
    }
  } else {
    // pure 3D
    var remaining = currentSection.workPlane;
    if (!isSameDirection(remaining.forward, new Vector(0, 0, 1)) || currentSection.isMultiAxis()) {
      error("\r\n_________________________________________" +
         "\r\n|              error                     |" +
         "\r\n|                                        |" +
         "\r\n| Tool orientation detected.             |" +
         "\r\n| You have to enable the property        |" +
         "\r\n| rotationAxisSetup                      |" +
         "\r\n| rotherwise you can only post           |" +
         "\r\n| 3 Axis programs.                       |" +
         "\r\n| If you still have issues,              |" +
         "\r\n| please contact www.DATRON.com!         |" +
         "\r\n|________________________________________|\r\n");
      return;
    }
    setRotation(remaining);
  }
  
  forceAny();

  if (properties.showNotes && currentSection.hasParameter("notes")) {
    var notes = currentSection.getParameter("notes");
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

  var clearance = getFramePosition(currentSection.getInitialPosition()).z;
  writeBlock("SafeZHeightForWorkpiece=" + xyzFormat.format(clearance));

  // write the optional length offset for each operation
  if (properties.useZAxisOffset) {
    writeBlock("ZAxisOffset = 0");
  }

  // radius Compensation
  var compensationType;
  if (hasParameter("operation:compensationType")) {
    compensationType = getParameter("operation:compensationType");
  } else {
    compensationType = "computer";
  }

  var wearCompensation;
  if (hasParameter("operation:compensationDeltaRadius")) {
    wearCompensation = getParameter("operation:compensationDeltaRadius");
  } else {
    wearCompensation = 0;
  }

  if (properties.writePathOffset) {
    switch (compensationType) {
    case "computer":
      break;
    case "control":
      writeBlock("PathOffset = 0");
      break;
    case "wear":
      writeBlock("PathOffset = " + dimensionFormat.format(wearCompensation));
      break;
    case "inverseWear":
      writeBlock("PathOffset = " + dimensionFormat.format(wearCompensation));
      break;
    }
  }

  if (!isProbeOperation(currentSection) && !isInspectionOperation(currentSection)) {

    // set coolant after we have positioned at Z
    setCoolant(tool.coolant);

    // tool changer command
    if (properties.writeToolTable) {
      writeBlock("Tool name=" + "\"" + createToolName(tool) + "\"" +
        " newRpm=" + rpmFormat.format(spindleSpeed) +
        " skipRestoring"
      );
    } else {
      writeBlock("Tool = " + toolOutput.format(tool.number) +
        " newRpm=" + rpmFormat.format(spindleSpeed) +
        " skipRestoring"
      );
    }

    //preload the next tool for the Datron tool assist
    if (properties.preloadTool) {
      var nextTool = getNextTool(tool.number);
      if (nextTool) {
        if (properties.writeToolTable) {
          writeBlock("ProvideTool name=" + "\"" + createToolName(nextTool) +  "\"");
        } else {
          writeBlock("ProvideTool = " + toolOutput.format(nextTool.number));
        }
      }
    }

    // set the current feed
    // replace by the default feed command
    if (properties.useParametricFeed && !(currentSection.hasAnyCycle && currentSection.hasAnyCycle())) {
      activeFeeds = initializeActiveFeeds(currentSection);
      if (useDatronFeedCommand) {
        var datronFeedParameter = new Array();
        for (var j = 0; j < activeFeeds.length; ++j) {
          var feedContext = activeFeeds[j];
          var datronFeedCommand = {
            name : feedContext.datronFeedName,
            feed : feedFormat.format(feedContext.feed)
          };
/*eslint-disable*/
          var indexOfFeedContext = datronFeedParameter.map(function(e) {return e.name;}).indexOf(datronFeedCommand.name);
          /*eslint-enable*/
          if (indexOfFeedContext == -1) {
            datronFeedParameter.push(datronFeedCommand);
          } else {
            var existingFeedContext = datronFeedParameter[indexOfFeedContext];
            if (existingFeedContext.feed < datronFeedCommand.feed) {
              existingFeedContext.feed = datronFeedCommand.feed;
            }
          }
        }
        var datronFeedCommand = "SetFeedTechnology";
        for (var i = 0; i < datronFeedParameter.length; i++) {
          datronFeedCommand += " " + datronFeedParameter[i].name + "=" + datronFeedParameter[i].feed;
        }
        writeBlock(datronFeedCommand);

      } else {
        for (var j = 0; j < activeFeeds.length; ++j) {
          var feedContext = activeFeeds[j];
          writeBlock(formatVariable(feedContext.description) + " = " + feedFormat.format(feedContext.feed) + (unit == MM ? " # mm/min!" : " # in/min!"));
        }
      }
    }
  }

  // parameter for the sequences
  var sequenceParamter = new Array();

  if (hasParameter("operation:cycleType")) {

    //Reset all movements to suppress older entries...
    activeMovements = new Array();

    var cycleType = getParameter("operation:cycleType");
    writeComment("Parameter " + cycleType + " cycle");

    switch (cycleType) {
    case "thread-milling":
      writeBlock("SetFeedTechnology" + " ramp=" + feedFormat.format(getParameter("movement:cutting")) + " finishing=" + feedFormat.format(getParameter("movement:finish_cutting")));
      var diameter = currentSection.getParameter("diameter");
      var pitch = currentSection.getParameter("pitch");
      var finishing = parseFloat(currentSection.getParameter("stepover"));
      
      writeBlock("nominalDiameter=" + xyzFormat.format(diameter));
      sequenceParamter.push("nominalDiameter=nominalDiameter");
      writeBlock("pitch=" + xyzFormat.format(pitch));
      sequenceParamter.push("pitch=pitch");
 
      if (!isNaN(finishing)) {
        writeBlock("finishing=" + xyzFormat.format(finishing));
        sequenceParamter.push("finishing=finishing");
      } else {
        sequenceParamter.push("finishing=0");
      }
      /*
      writeBlock('threadName="M' +  toolFormat.format(diameter) + '"');
      sequenceParamter.push('threadName=threadName');
      writeBlock("threading = " + currentSection.getParameter("threading"));
      sequenceParamter.push("threading=threading");

      TAG: den Standard auch mit Imperial unterstuezten
      sequenceParamter.push("threadStandard=ThreadStandards.Metric");
      sequenceParamter.push("deburring=ThreadMillingDeburring.NoDeburring");
      sequenceParamter.push("insideOutside=ThreadMillingSide.Inside");
      sequenceParamter.push("direction=ThreadMillingDirection.RightHandThread");
      writeBlock("direction = " + dimensionFormat.format(currentSection.getParameter("direction")));
      sequenceParamter.push("direction=direction");
      writeBlock("repeatPass = " + dimensionFormat.format(currentSection.getParameter("repeatPass")));
      sequenceParamter.push("repeatPass=repeatPass");
*/
      break;
    case "bore-milling":
      writeBlock("SetFeedTechnology roughing=" + feedFormat.format(getParameter("movement:cutting")) + " finishing=" + feedFormat.format(getParameter("movement:cutting")));
      writeBlock("diameter = " + dimensionFormat.format(currentSection.getParameter("diameter")));
      sequenceParamter.push("diameter=diameter");

      writeBlock("infeedZ = " + dimensionFormat.format(currentSection.getParameter("pitch")));
      sequenceParamter.push("infeedZ=infeedZ");
      writeBlock("repeatPass = " + dimensionFormat.format(currentSection.getParameter("repeatPass")));
      sequenceParamter.push("repeatPass=repeatPass");
      break;
    case "drilling":
      writeBlock("SetFeedTechnology plunge=" + feedFormat.format(getParameter("movement:plunge")));
      break;
    case "chip-breaking":
      writeBlock("SetFeedTechnology plunge=" + feedFormat.format(getParameter("movement:plunge")) + " roughing=" + feedFormat.format(getParameter("movement:cutting")));
      writeBlock("infeedZ = " + dimensionFormat.format(currentSection.getParameter("incrementalDepth")));
      sequenceParamter.push("infeedZ=infeedZ");
      break;
    }
  }

  if (properties.useSequences && !isProbeOperation(currentSection) && !isInspectionOperation(currentSection)) {
    // call sequence
    if (properties.useParametricFeed && (!useDatronFeedCommand) && !(currentSection.hasAnyCycle && currentSection.hasAnyCycle())) {
      activeFeeds = initializeActiveFeeds(currentSection);
      for (var j = 0; j < activeFeeds.length; ++j) {
        var feedContext = activeFeeds[j];
        sequenceParamter.push(formatVariable(feedContext.description) + "=" + formatVariable(feedContext.description));
      }
    }
    var currentSectionCall = getSequenceName(currentSection) + " " + sequenceParamter.join(" ");
    writeBlock(currentSectionCall);

    // write sequence
    var currentSequenceName = getSequenceName(currentSection);
    if (properties.useExternalSequencesFiles) {
      spacingDepth -= 1;
      var filename = getOutputPath();
      //sequenceFilePath = filename.substr(0, filename.lastIndexOf(".")) + "_" + currentSequenceName + ".seq";
      sequenceFilePath = FileSystem.getFolderPath(getOutputPath()) + "\\";
      sequenceFilePath += currentSequenceName + ".seq";
      redirectToFile(sequenceFilePath);
    } else {
      setWriteRedirection(sequenceBuffer);
      writeBlock(" ");
      // TAG: modify parameter
      spacingDepth -= 1;
      writeBlock("$$$ " + currentSequenceName);
    }
  }

  if (!isProbeOperation(currentSection) && !isInspectionOperation(currentSection)) {
    writeBlock(spindleSpeed > 100 ? "Spindle On" : "Spindle Off");
  } else {
    writeBlock("Spindle Off");
    writeBlock("PrepareXyzSensor");
  }

  // move to initial Position (this command move the Z Axis to safe high and repositioning in safe high after that drive Z to end position)
  var initialPosition = getFramePosition(currentSection.getInitialPosition());
  var xyz = xOutput.format(initialPosition.x) + yOutput.format(initialPosition.y) + zOutput.format(initialPosition.z);

  writeBlock("PrePositioning" + xyz);

  // adds support for suction
  if (properties.useSuction) {
    writeBlock("Suction On");
  }
  // surface Inspection
  if (isInspectionOperation(currentSection) && (typeof inspectionProcessSectionStart == "function")) {
    inspectionProcessSectionStart();
  }
  
}

function showWaitDialog(operationName) {
  writeBlock("showWaitDialog operationName=\"" + operationName + "\"");
}

function writeWaitProgram() {
  waitProgram = new Array();
  waitProgram.push("#Show the wait dialog for the next operation\r\n");
  waitProgram.push("program showWaitDialog optional operationName:string\r\n");
  waitProgram.push("  if not operationName hasvalue \r\n");
  waitProgram.push("    operationName =" + "\"" + "\"\r\n");
  waitProgram.push("  endif\r\n");
  waitProgram.push("\r\n");
  waitProgram.push("  messageString = " + "\"" + "Start next Operation\r"  + "\"" + "  + operationName \r\n");
  waitProgram.push("  dialogRes = System::Dialog message=messageString caption=" + "\"" + "Start next Operation?" + "\"" + "Yes  Cancel\r\n");
  waitProgram.push("  if dialogRes == System::DialogResult.Cancel\r\n");
  waitProgram.push("    exit\r\n");
  waitProgram.push("  endif\r\n");
  waitProgram.push("endprogram\r\n");

  waitProgramOperation = {operationProgram: waitProgram};
  SimPLProgram.operationList.push(waitProgramOperation);
}

function onDwell(seconds) {
  writeBlock("Sleep " + "milliseconds=" + sleepFormat.format(seconds));
}

function onSpindleSpeed(spindleSpeed) {
  // writeBlock("Rpm=" + rpmFormat.format((spindleSpeed < 6000) ? 6000 : spindleSpeed));
  writeBlock("Rpm=" + rpmFormat.format(spindleSpeed));
}

var pendingRadiusCompensation = -1;

function onRadiusCompensation() {
  pendingRadiusCompensation = radiusCompensation;
}

function onRapid(x, y, z) {
  var xyz = "";
  xyz += (x !== null) ? xOutput.format(x) : "";
  xyz += (y !== null) ? yOutput.format(y) : "";
  xyz += (z !== null) ? zOutput.format(z) : "";

  if (xyz) {
    if (pendingRadiusCompensation >= 0) {
      error(localize("Radius compensation mode cannot be changed at rapid traversal."));
      return;
    }
    writeBlock("Rapid" + xyz);
    forceFeed();
  }
}

function onPrePositioning(x, y, z) {
  var xyz = "";
  xyz += (x !== null) ? xOutput.format(x) : "";
  xyz += (y !== null) ? yOutput.format(y) : "";
  xyz += (z !== null) ? zOutput.format(z) : "";

  if (xyz) {
    if (pendingRadiusCompensation >= 0) {
      error(localize("Radius compensation mode cannot be changed at rapid traversal."));
      return;
    }
    writeBlock("PrePositioning" + xyz);
    forceFeed();
  }
}

function onLinear(x, y, z, feed) {
  if (isInspectionOperation(currentSection)) {
    onExpandedRapid(x, y, z);
    return;
  }
  var xyz = "";
  xyz += (x !== null) ? xOutput.format(x) : "";
  xyz += (y !== null) ? yOutput.format(y) : "";
  xyz += (z !== null) ? zOutput.format(z) : "";

  var f = getFeed(feed);

  if (pendingRadiusCompensation >= 0) {
    pendingRadiusCompensation = -1;
    var d = tool.diameterOffset;
    if (d > 99) {
      warning(localize("The diameter offset exceeds the maximum value."));
    }
    // TAG: um die Ebenen kuemmern
    // writeBlock(gPlaneModal.format(17));
    var compensationType = null;
    if (currentSection.hasParameter("operation:compensationType")) {
      compensationType = currentSection.getParameter("operation:compensationType");
    }
    
    switch (radiusCompensation) {
    case RADIUS_COMPENSATION_LEFT:
      switch (compensationType) {
      case "control":
        writeBlock("ToolCompensation Left");
        writeBlock("PathCorrection Left");
        break;
      case "wear":
      case "inverseWear":
        writeBlock("PathCorrection Left");
        break;
      default:
        writeBlock("ToolCompensation Off");
        writeBlock("PathCorrection Off");
        break;
      }
      break;
    case RADIUS_COMPENSATION_RIGHT:
      switch (compensationType) {
      case "control":
        writeBlock("ToolCompensation Rigth");
        writeBlock("PathCorrection Rigth");
        break;
      case "wear":
      case "inverseWear":
        writeBlock("PathCorrection Rigth");
        break;
      default:
        writeBlock("ToolCompensation Off");
        writeBlock("PathCorrection Off");
        break;
      }
      break;
    case RADIUS_COMPENSATION_OFF:
      writeBlock("ToolCompensation Off");
      writeBlock("PathCorrection Off");
      break;
    }
  }

  if (xyz) {
    if (f) {
      writeBlock(f);
    }
    writeBlock("Line" + xyz);
  }
}

function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {
  // one of X/Y and I/J are required and likewise
  var f = getFeed(feed);

  if (f) {
    writeBlock(f);
  }

  if (pendingRadiusCompensation >= 0) {
    error(localize("radius compensation cannot be activated/deactivated for a circular move."));
    return;
  }

  var start = getCurrentPosition();

  if (isFullCircle()) {
    if (isHelical()) {
      linearize(tolerance);
      return;
    }
    // TAG: are 360deg arcs supported
    switch (getCircularPlane()) {
    case PLANE_XY:
      writeBlock("Arc" +
        (clockwise ? " CW" : " CCW") +
        xOutput.format(x) +
        iOutput.format(cx - start.x) +
        jOutput.format(cy - start.y)
      );
      break;
    default:
      linearize(tolerance);
    }
  } else {
    switch (getCircularPlane()) {
    case PLANE_XY:
      writeBlock("Arc" +
        (clockwise ? " CW" : " CCW") +
        xOutput.format(x) +
        yOutput.format(y) +
        zOutput.format(z) +
        iOutput.format(cx - start.x) +
        jOutput.format(cy - start.y)
      );
      break;
    default:
      linearize(tolerance);
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
  var a = aOutput.format(_a);
  var b = bOutput.format(_b);
  var c = cOutput.format(_c);

  forceABC();
  var xyzabc = x + y + z + a + b + c;
  writeBlock("Rapid" + xyzabc);
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
  var a = aOutput.format(_a);
  var b = bOutput.format(_b);
  var c = cOutput.format(_c);
  var f = getFeed(feed);
  
  if (f) {
    writeBlock(f);
  }
  if (x || y || z || a || b || c) {
    var xyzabc = x + y + z + a + b + c;
    writeBlock("Line" + xyzabc);
  }
  //else if (f) {
  //   if (getNextRecord().isMotion()) { // try not to output feed without motion
  //     forceFeed(); // force feed on next line
  //   } else {
  //     writeBlock(getFeed(feed));
  //   }
  // }
}

function onRewindMachine(a, b, c) {
  writeBlock("MoveToSafetyPosition");
  var abc = aOutput.format(a) + bOutput.format(b) + cOutput.format(c);
  writeBlock("Line" + abc);
}

var currentCoolantMode = COOLANT_OFF;

function setCoolant(coolant) {
  if (properties.writeCoolantCommands) {
    if (coolant == COOLANT_OFF) {
      writeBlock("SpraySystem Off");
      currentCoolantMode = COOLANT_OFF;
      return;
    }

    switch (coolant) {
    case COOLANT_FLOOD:
    case COOLANT_MIST:
      writeBlock("SprayTechnology External");
      writeBlock("Coolant Alcohol");
      break;
    case COOLANT_AIR:
      writeBlock("SprayTechnology External");
      writeBlock("Coolant Air");
      break;
    case COOLANT_THROUGH_TOOL:
      writeBlock("SprayTechnology Internal");
      writeBlock("Coolant Alcohol");
      break;
    case COOLANT_AIR_THROUGH_TOOL:
      writeBlock("SprayTechnology Internal");
      writeBlock("Coolant Air");
      break;
      
    default:
      onUnsupportedCoolant(coolant);
    }
    writeBlock("SpraySystem On");
    currentCoolantMode = coolant;
  }
}

var isInsideProgramDeclaration = false;
var directNcOperation;
function parseManualNc(text) {
 
  // eslint-disable-next-line no-useless-escape
  var modulePattern = new RegExp("\.*(using|import)");
  var isModuleImport = modulePattern.test(text);
  if (isModuleImport) {
    SimPLProgram.usingList.push(text);
    return;
  }
 
  var programPattern = /(?:\s*program\s+)(\w+)/;
  var isProgramDeclaration = programPattern.test(text);

  if (isProgramDeclaration) {
    var subProgramName =  programPattern.exec(text);
    if (subProgramName == undefined) {return;}
    directNcOperation = {operationCall:subProgramName[1], operationProgram: new StringBuffer()};
    SimPLProgram.operationList.push(directNcOperation);
    isInsideProgramDeclaration = true;
  }

  var isEndProgram = (/\s*endprogram/).test(text);
  if (isEndProgram) {
    isInsideProgramDeclaration = false;
    directNcOperation.operationProgram.append(text + "\r\n");
    return;
  }

  if (isInsideProgramDeclaration) {
    directNcOperation.operationProgram.append(text + "\r\n");
    return;
  }

  return;
}

function onManualNC(command, value) {
  switch (command) {
  case 42: // Manual NC enumeration code ???
    value = parseManualNc(value);
    break;
  case 40:  // Comment
    value = "# " + value;
    break;
  case 41: //wait
    value = "Sleep seconds=" + value;
    break;
  case COMMAND_COOLANT_OFF:
    value = "SpraySystem Off";
    break;
  case COMMAND_COOLANT_ON:
    value = "SpraySystem On";
    break;
  case COMMAND_STOP:
    value = "break";
    break;
  case COMMAND_START_SPINDLE:
    value = "Spindle On";
    break;
  case COMMAND_LOCK_MULTI_AXIS:
    return;
  case COMMAND_UNLOCK_MULTI_AXIS:
    return;
  case COMMAND_START_CHIP_TRANSPORT:
    value = "ChipConveyor On";
    break;
  case COMMAND_STOP_CHIP_TRANSPORT:
    value = "ChipConveyor Off";
    break;
  case COMMAND_OPEN_DOOR: //open door
    value = "ReleaseDoor";
    break;
  case COMMAND_CLOSE_DOOR: //close door not needed
    return;
  case COMMAND_CALIBRATE: //calibrate
    value = "# calibration currently not supported!";
    break;
  case COMMAND_VERIFY: // check part
    value = "Dialog message=\"Please check workpiece!\" Ok Cancel caption=\"Cam generated dialog\"";
    break;
  case COMMAND_CLEAN: // clean part
    value = "Dialog message=\"Please clean workpiece!\" Ok Cancel caption=\"Cam generated dialog\"";
    break;
  case 43: // action no idea for what has a paramter
    value = "# Action currently not supported!";
    break;
  case 44: // print message
    // value = 'Dialog message="' + value + '" Ok Cancel caption="Cam generated dialog"'
    SimPLProgram.usingList.push("using File");
    SimPLProgram.usingList.push("using DateTimeModule");
    var message = (" value=(GetNow + \"\t" + value + "\")");
    value = "FileWriteLine filename=\"" + getFilename() + ".log\""  + message;
    break;
  case 46: // show message
    value = "StatusMessage message=\"" + value + "\"";
    break;
  case COMMAND_ALARM: // alarm
    value = "Dialog message=\"Alarm!\" Ok Cancel caption=\"Cam generated dialog\"";
    break;
  case COMMAND_ALERT: // alarm
    value = "Dialog message=\"Warning!\" Ok Cancel caption=\"Cam generated dialog\"";
    break;
  case COMMAND_BREAK_CONTROL:
    value = "MeasureToolLength";
    break;
  case COMMAND_TOOL_MEASURE:
    value = "MeasureToolLength";
    break;
  case COMMAND_OPTIONAL_STOP:
    value = "OptionalBreak";
    break;
  case 45: //call subprogram
    var subprogramName = "SubProgram_" + SimPLProgram.externalUsermodules.length;
    SimPLProgram.externalUsermodules.push("usermodule " + subprogramName + "=\"" + value + "\"");
    value = subprogramName;
    break;
  }

  if (value != undefined) {
    var operation = {operationCall: value, operationProgram:""};
    SimPLProgram.operationList.push(operation);
  }
}

var mapCommand = {};

var passThrough = new Array();
function onPassThrough(text) {
  passThrough.push(text);
}

function onCommand(command) {
  switch (command) {
  case COMMAND_PROBE_ON:
    return;
  case COMMAND_PROBE_OFF:
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

function onCycle() {
}

function onCycleEnd() {
}

function isProbeOperation(section) {
  return (section.hasParameter("operation-strategy") && ((section.getParameter("operation-strategy") == "probe" || section.getParameter("operation-strategy") == "probe_geometry")));
}

function isInspectionOperation(section) {
  return section.hasParameter("operation-strategy") && (section.getParameter("operation-strategy") == "inspectSurface");
}

function approach(value) {
  validate((value == "positive") || (value == "negative"), "Invalid approach.");
  return (value == "positive") ? 1 : -1;
}

function onCyclePoint(x, y, z) {
  if (cycleType == "inspect") {
    if (typeof inspectionCycleInspect == "function") {
      inspectionCycleInspect(cycle, x, y, z);
      return;
    } else {
      cycleNotSupported();
    }
  }
  var feedString = feedOutput.format(cycle.feedrate);
  var probeWCS = hasParameter("operation-strategy") && (getParameter("operation-strategy") == "probe");

  if (isProbeOperation(currentSection)) {
    if (!isSameDirection(currentSection.workPlane.forward, new Vector(0, 0, 1)) && (!cycle.probeMode || (cycle.probeMode == 0))) {
      error(localize("Updating WCS / work offset using probing is only supported by the CNC in the WCS frame."));
      return;
    }
  
    var startPositionOffset = cycle.probeClearance + tool.cornerRadius;
  }

  switch (cycleType) {
  case "bore-milling":
    for (var i = 0; i <= cycle.repeatPass; ++i) {
      forceXYZ();
      onRapid(x, y, cycle.clearance);
      boreMilling(cycle);
      onRapid(x, y, cycle.clearance);
    }
    break;
  case "thread-milling":
    for (var i = 0; i <= cycle.repeatPass; ++i) {
      forceXYZ();
      onRapid(x, y, cycle.clearance);
      threadMilling(cycle);
      onRapid(x, y, cycle.clearance);
    }
    break;
  case "drilling":
    forceXYZ();
    onRapid(x, y, cycle.clearance);
    drilling(cycle);
    onRapid(x, y, cycle.clearance);
    break;
    /*
  case "chip-breaking":
    forceXYZ();
    onRapid(x, y, null);
    onRapid(x, y, cycle.retract);
    chipBreaking(cycle);
    onRapid(x, y, cycle.clearance);
    break;
*/

  case "tapping":
  case "left-tapping":
  case "right-tapping":
  case "tapping-with-chip-breaking":
  case "left-tapping-with-chip-breaking":
  case "right-tapping-with-chip-breaking":
    forceXYZ();
    onRapid(x, y, cycle.clearance);
    tapping(cycle);
    onRapid(x, y, cycle.clearance);
    break;
  case "probing-x":
    forceXYZ();
    onRapid(x, y, cycle.stock);
    onLinear(x, y, (z - cycle.depth + tool.cornerRadius), cycle.feedrate);
   
    var measureString = "measResult = EdgeMeasure ";
    measureString += (cycle.approach1 == "positive" ? "XPositive" : "XNegative");
    measureString += " searchDistance=" + xyzFormat.format(cycle.probeClearance);
    if (probeWCS) {
      measureString += " originShift=" + xyzFormat.format(-1 * (x + approach(cycle.approach1) * startPositionOffset));
      writeBlock(measureString);
    } else {
      measureString += " None";
      writeBlock(measureString);
      expectedArgs = (
        "expectedXPos=" +  xyzFormat.format(x + approach(cycle.approach1) * startPositionOffset) +
        " measureDirectionX=" + (cycle.approach1 == "positive" ? "positive" : "negative")
      );
      writeBlock(getProbingArguments(cycle, undefined, expectedArgs));
    }
    break;
  case "probing-y":
    forceXYZ();
    onRapid(x, y, cycle.stock);
    onLinear(x, y, (z - cycle.depth + tool.cornerRadius), cycle.feedrate);
    
    var measureString = "measResult = EdgeMeasure ";
    measureString += (cycle.approach1 == "positive" ? "YPositive" : "YNegative");
    measureString += " searchDistance=" + xyzFormat.format(cycle.probeClearance);
    if (probeWCS) {
      measureString += " originShift=" + xyzFormat.format(-1 * (y + approach(cycle.approach1) * startPositionOffset));
      writeBlock(measureString);
    } else {
      measureString += " None";
      writeBlock(measureString);
      expectedArgs = (
        "expectedYPos=" + xyzFormat.format(y + approach(cycle.approach1) * startPositionOffset) +
        " measureDirectionY=" + (cycle.approach1 == "positive" ? "positive" : "negative")
      );
      writeBlock(getProbingArguments(cycle, undefined, expectedArgs));
    }
    break;
  case "probing-z":
    forceXYZ();
    onRapid(x, y, cycle.stock);
    onLinear(x, y, (Math.min(z - cycle.depth + cycle.probeClearance, cycle.retract)), cycle.feedrate);
  
    var measureString = "measResult = SurfaceMeasure ";
    if (probeWCS) {
      measureString += " originZShift=" + xyzFormat.format(z - cycle.depth);
      writeBlock(measureString);
    } else {
      measureString += " None";
      writeBlock(measureString);
      expectedArgs = (
        "expectedZPos=" + xyzFormat.format(z - cycle.depth)
      );
      writeBlock(getProbingArguments(cycle, undefined, expectedArgs));
    }
    break;
  case "probing-x-wall":
    var measureString = "measResult = SymmetryAxisMeasure";
    measureString += " width=" + cycle.width1;
    measureString += " searchDistance=" + cycle.probeClearance;
    measureString += " measureZOffset=" + (z - cycle.depth + tool.diameter / 2);
    measureString += " Outside";
    measureString += " YAligned";
    measureString += " skipZMeasure";
    if (probeWCS) {
      measureString += " originXShift=" + xyzFormat.format(-x);
      writeBlock(measureString);
    } else {
      measureString += " None";
      writeBlock(measureString);
      expectedArgs = (
        "expectedXPos=" + xyzFormat.format(x) +
        " expectedDimensionX=" + xyzFormat.format(cycle.width1)
      );
      writeBlock(getProbingArguments(cycle, undefined, expectedArgs));
    }
    break;
  case "probing-y-wall":
    var measureString = "measResult = SymmetryAxisMeasure";
    measureString += " width=" + cycle.width1;
    measureString += " searchDistance=" + cycle.probeClearance;
    measureString += " measureZOffset=" + (z - cycle.depth + tool.diameter / 2);
    measureString += " Outside";
    measureString += " XAligned";
    measureString += " skipZMeasure";
    if (probeWCS) {
      measureString += " originYShift=" + xyzFormat.format(-y);
      writeBlock(measureString);
    } else {
      measureString += " None";
      writeBlock(measureString);
      expectedArgs = (
        "expectedYPos=" + xyzFormat.format(y) +
        " expectedDimensionY=" + xyzFormat.format(cycle.width1)
      );
      writeBlock(getProbingArguments(cycle, undefined, expectedArgs));
    }
    break;
  case "probing-x-channel":
    var measureString = "measResult = SymmetryAxisMeasure";
    measureString += " width=" + cycle.width1;
    measureString += " searchDistance=" + cycle.probeClearance;
    measureString += " measureZOffset=" + (z - cycle.depth + tool.diameter / 2);
    measureString += " Inside";
    measureString += " YAligned";
    measureString += " skipZMeasure";
    if (probeWCS) {
      measureString += " originXShift=" + xyzFormat.format(-x);
      writeBlock(measureString);
    } else {
      measureString += " None";
      writeBlock(measureString);
      expectedArgs = (
        "expectedXPos=" + xyzFormat.format(x) +
        " expectedDimensionX=" + xyzFormat.format(cycle.width1)
      );
      writeBlock(getProbingArguments(cycle, undefined, expectedArgs));
    }
    break;
  case "probing-x-channel-with-island":
    var measureString = "measResult = SymmetryAxisMeasure";
    measureString += " width=" + cycle.width1;
    measureString += " searchDistance=" + cycle.probeClearance;
    measureString += " measureZOffset=" + (z - cycle.depth + tool.diameter / 2);
    measureString += " Inside";
    measureString += " YAligned";
    measureString += " forceSafeHeight";
    measureString += " skipZMeasure";
    if (probeWCS) {
      measureString += " originXShift=" + xyzFormat.format(-x);
      writeBlock(measureString);
    } else {
      measureString += " None";
      writeBlock(measureString);
      expectedArgs = (
        "expectedXPos=" + xyzFormat.format(x) +
        " expectedDimensionX=" + xyzFormat.format(cycle.width1)
      );
      writeBlock(getProbingArguments(cycle, undefined, expectedArgs));
    }
    break;
  case "probing-y-channel":
    var measureString = "measResult = SymmetryAxisMeasure";
    measureString += " width=" + cycle.width1;
    measureString += " searchDistance=" + cycle.probeClearance;
    measureString += " measureZOffset=" + (z - cycle.depth + tool.diameter / 2);
    measureString += " Inside";
    measureString += " XAligned";
    measureString += " skipZMeasure";
    if (probeWCS) {
      measureString += " originYShift=" + xyzFormat.format(-y);
      writeBlock(measureString);
    } else {
      measureString += " None";
      writeBlock(measureString);
      expectedArgs = (
        "expectedYPos=" + xyzFormat.format(y) +
        " expectedDimensionY=" + xyzFormat.format(cycle.width1)
      );
      writeBlock(getProbingArguments(cycle, undefined, expectedArgs));
    }
    break;
  case "probing-y-channel-with-island":
    var measureString = "measResult = SymmetryAxisMeasure";
    measureString += " width=" + cycle.width1;
    measureString += " searchDistance=" + cycle.probeClearance;
    measureString += " measureZOffset=" + (z - cycle.depth + tool.diameter / 2);
    measureString += " Inside";
    measureString += " XAligned";
    measureString += " forceSafeHeight";
    measureString += " skipZMeasure";
    if (probeWCS) {
      measureString += " originYShift=" + xyzFormat.format(-y);
      writeBlock(measureString);
    } else {
      measureString += " None";
      writeBlock(measureString);
      expectedArgs = (
        "expectedYPos=" + xyzFormat.format(y) +
        " expectedDimensionY=" + xyzFormat.format(cycle.width1)
      );
      writeBlock(getProbingArguments(cycle, undefined, expectedArgs));
    }
    break;
  case "probing-xy-circular-boss":
    var measureString = "measResult = CircleMeasure";
    measureString += " diameter=" + cycle.width1;
    measureString += " searchDistance=" + cycle.probeClearance;
    measureString += " measureZPos=" + (z - cycle.depth + tool.diameter / 2);
    measureString += " Outside";
    measureString += " skipZMeasure";
    if (probeWCS) {
      measureString += " originXShift=" + xyzFormat.format(-x);
      measureString += " originYShift=" + xyzFormat.format(-y);
      writeBlock(measureString);
    } else {
      measureString += " None";
      writeBlock(measureString);
      expectedArgs = (
        "expectedXPos=" +  xyzFormat.format(x) +
        " expectedYPos=" + xyzFormat.format(y) +
        " expectedDimensionX=" + xyzFormat.format(cycle.width1)
      );
      writeBlock(getProbingArguments(cycle, undefined, expectedArgs));
    }
    break;
  case "probing-xy-circular-hole":
    var measureString = "measResult = CircleMeasure";
    measureString += " diameter=" + cycle.width1;
    measureString += " searchDistance=" + cycle.probeClearance;
    measureString += " measureZPos=" + (z - cycle.depth + tool.diameter / 2);
    measureString += " Inside";
    measureString += " skipZMeasure";
    if (probeWCS) {
      measureString += " originXShift=" + xyzFormat.format(-x);
      measureString += " originYShift=" + xyzFormat.format(-y);
      writeBlock(measureString);
    } else {
      measureString += " None";
      writeBlock(measureString);
      expectedArgs = (
        "expectedXPos=" +  xyzFormat.format(x) +
        " expectedYPos=" + xyzFormat.format(y) +
        " expectedDimensionX=" + xyzFormat.format(cycle.width1)
      );
      writeBlock(getProbingArguments(cycle, undefined, expectedArgs));
    }
    break;
  case "probing-xy-circular-hole-with-island":
    var measureString = "measResult = CircleMeasure";
    measureString += " diameter=" + cycle.width1;
    measureString += " searchDistance=" + cycle.probeClearance;
    measureString += " measureZPos=" + (z - cycle.depth + tool.diameter / 2);
    measureString += " Inside";
    measureString += " forceSafeHeight";
    measureString += " skipZMeasure";
    if (probeWCS) {
      measureString += " originXShift=" + xyzFormat.format(-x);
      measureString += " originYShift=" + xyzFormat.format(-y);
      writeBlock(measureString);
    } else {
      measureString += " None";
      writeBlock(measureString);
      expectedArgs = (
        "expectedXPos=" +  xyzFormat.format(x) +
        " expectedYPos=" + xyzFormat.format(y) +
        " expectedDimensionX=" + xyzFormat.format(cycle.width1)
      );
      writeBlock(getProbingArguments(cycle, undefined, expectedArgs));
    }
    break;
  case "probing-xy-rectangular-boss":
    var measureString = "measResult = RectangleMeasure";
    measureString += " dimensionX=" + cycle.width1;
    measureString += " dimensionY=" + cycle.width2;
    measureString += " searchDistance=" + cycle.probeClearance;
    measureString += " xMeasureZOffset=" + (z - cycle.depth + tool.diameter / 2);
    measureString += " yMeasureZOffset=" + (z - cycle.depth + tool.diameter / 2);
    measureString += " Outside";
    measureString += " Center";
    measureString += " skipZMeasure";
    if (probeWCS) {
      measureString += " originXShift=" + xyzFormat.format(-x);
      measureString += " originYShift=" + xyzFormat.format(-y);
      writeBlock(measureString);
    } else {
      measureString += " None";
      writeBlock(measureString);
      expectedArgs = (
        "expectedXPos=" +  xyzFormat.format(x) +
        " expectedYPos=" + xyzFormat.format(y) +
        " expectedDimensionX=" + xyzFormat.format(cycle.width1) +
        " expectedDimensionY=" + xyzFormat.format(cycle.width2)
      );
      writeBlock(getProbingArguments(cycle, undefined, expectedArgs));
    }
    break;
  case "probing-xy-rectangular-hole":
    var measureString = "measResult = RectangleMeasure";
    measureString += " dimensionX=" + cycle.width1;
    measureString += " dimensionY=" + cycle.width2;
    measureString += " searchDistance=" + cycle.probeClearance;
    measureString += " xMeasureZOffset=" + (z - cycle.depth + tool.diameter / 2);
    measureString += " yMeasureZOffset=" + (z - cycle.depth + tool.diameter / 2);
    measureString += " Inside";
    measureString += " Center";
    measureString += " skipZMeasure";
    if (probeWCS) {
      measureString += " originXShift=" + xyzFormat.format(-x);
      measureString += " originYShift=" + xyzFormat.format(-y);
      writeBlock(measureString);
    } else {
      measureString += " None";
      writeBlock(measureString);
      expectedArgs = (
        "expectedXPos=" +  xyzFormat.format(x) +
        " expectedYPos=" + xyzFormat.format(y) +
        " expectedDimensionX=" + xyzFormat.format(cycle.width1) +
        " expectedDimensionY=" + xyzFormat.format(cycle.width2)
      );
      writeBlock(getProbingArguments(cycle, undefined, expectedArgs));
    }
    break;
  case "probing-xy-rectangular-hole-with-island":
    var measureString = "measResult = RectangleMeasure";
    measureString += " dimensionX=" + cycle.width1;
    measureString += " dimensionY=" + cycle.width2;
    measureString += " searchDistance=" + cycle.probeClearance;
    measureString += " xMeasureZOffset=" + (z - cycle.depth + tool.diameter / 2);
    measureString += " yMeasureZOffset=" + (z - cycle.depth + tool.diameter / 2);
    measureString += " Inside";
    measureString += " Center";
    measureString += " forceSafeHeight";
    measureString += " skipZMeasure";
    if (probeWCS) {
      measureString += " originXShift=" + xyzFormat.format(-x);
      measureString += " originYShift=" + xyzFormat.format(-y);
      writeBlock(measureString);
    } else {
      measureString += " None";
      writeBlock(measureString);
      expectedArgs = (
        "expectedXPos=" +  xyzFormat.format(x) +
        " expectedYPos=" + xyzFormat.format(y) +
        " expectedDimensionX=" + xyzFormat.format(cycle.width1) +
        " expectedDimensionY=" + xyzFormat.format(cycle.width2)
      );
      writeBlock(getProbingArguments(cycle, undefined, expectedArgs));
    }
    break;
  case "probing-xy-inner-corner":
    // This is the method that match the hsm preview but ;-) not with probing
    // var probingDepth = (z - cycle.depth + tool.cornerRadius);
    // var measureString = "measResult = EdgeMeasure ";

    // zOutput.reset();
    // onRapid(x, y, cycle.stock);
    // onLinear(x, y, probingDepth, cycle.feedrate);
    // measureString += (cycle.approach1 == "positive" ? "XPositive" : "XNegative");
    // measureString += " originShift=" + xyzFormat.format(-1 * (x + approach(cycle.approach1) * startPositionOffset));
    // measureString += " searchDistance=" + xyzFormat.format(cycle.probeClearance);
    // writeBlock(measureString);

    // forceXYZ();
    // //zOutput.reset();
    // onRapid(x, y, cycle.stock);
    // onLinear(x, y, probingDepth, cycle.feedrate);
    
    // var measureString = "measResult = EdgeMeasure ";
    // measureString += (cycle.approach1 == "positive" ? "YPositive" : "YNegative");
    // measureString += " originShift=" + xyzFormat.format(-1 * (y + approach(cycle.approach1) * startPositionOffset));
    // measureString += " searchDistance=" + xyzFormat.format(cycle.probeClearance);
    // writeBlock(measureString);

    var isXNeagtive = (cycle.approach1 == "negative");
    var isYNeagtive = (cycle.approach2 == "negative");
    
    var orientation = "";
    if (!isXNeagtive && !isYNeagtive) {
      orientation = "BackRight";
    }
    if (isXNeagtive && !isYNeagtive) {
      orientation = "BackLeft";
    }
    if (!isXNeagtive && isYNeagtive) {
      orientation = "FrontRight";
    }
    if (isXNeagtive && isYNeagtive) {
      orientation = "FrontLeft";
    }
   
    var measureString = "measResult = CornerMeasure";
    measureString += " " + orientation;
    measureString += " Inside";
    measureString += " xMeasureYOffset=" + xyzFormat.format(cycle.probeClearance);
    measureString += " yMeasureXOffset=" + xyzFormat.format(cycle.probeClearance);
    measureString += " searchDistance=" + xyzFormat.format(cycle.probeClearance);
    measureString += " xMeasureZOffset=" + (z - cycle.depth + tool.diameter / 2);
    measureString += " yMeasureZOffset=" + (z - cycle.depth + tool.diameter / 2);
    measureString += " forceSafeHeight";
    measureString += " skipZMeasure";
    if (probeWCS) {
      measureString += " originXShift=" + xyzFormat.format(-x);
      measureString += " originYShift=" + xyzFormat.format(-y);
      writeBlock(measureString);
    } else {
      measureString += " None";
      writeBlock(measureString);
      expectedArgs = (
        "expectedXPos=" +  xyzFormat.format(x) +
        " expectedYPos=" + xyzFormat.format(y) +
        " measureDirectionX=" + cycle.approach1 +
        " measureDirectionY=" + cycle.approach2
      );
      writeBlock(getProbingArguments(cycle, undefined, expectedArgs));
    }
    break;
  case "probing-xy-outer-corner":
    // This is the method that match the hsm preview but ;-) not with probing
    // var probingDepth = (z - cycle.depth + tool.cornerRadius);
    // var touchPositionX1 = x + approach(cycle.approach1) * (cycle.probeClearance + tool.diameter / 2 + cycle.probeOvertravel);
    // var touchPositionY1 = y + approach(cycle.approach2) * (cycle.probeClearance + tool.diameter / 2 + cycle.probeOvertravel);
    // var measureString = "measResult = EdgeMeasure ";

    // zOutput.reset();
    // onRapid(x, y, probingDepth);
    // onLinear(x, touchPositionY1, probingDepth, cycle.feedrate);
    // measureString += (cycle.approach1 == "positive" ? "XPositive" : "XNegative");
    // measureString += " originShift=" + xyzFormat.format(-1 * (x + approach(cycle.approach1) * startPositionOffset));
    // measureString += " searchDistance=" + xyzFormat.format(cycle.probeClearance);
    // writeBlock(measureString);
    // forceXYZ();
    // onLinear(x, touchPositionY1, probingDepth, cycle.feedrate);
    // onLinear(x, y, probingDepth, cycle.feedrate);
    // //forceXYZ();
    // //zOutput.reset();
    // onLinear(touchPositionX1, y, probingDepth, cycle.feedrate);
    // onLinear(touchPositionX1, y, probingDepth, cycle.feedrate);

    var measureString = "measResult = EdgeMeasure ";
    measureString += (cycle.approach1 == "positive" ? "YPositive" : "YNegative");
    measureString += " originShift=" + xyzFormat.format(-1 * (y + approach(cycle.approach1) * startPositionOffset));
    measureString += " searchDistance=" + xyzFormat.format(cycle.probeClearance);
    writeBlock(measureString);
    forceXYZ();
    onLinear(touchPositionX1, y, probingDepth, cycle.feedrate);
    onLinear(x, y, probingDepth, cycle.feedrate);

    var isXNeagtive = (cycle.approach1 == "negative");
    var isYNeagtive = (cycle.approach2 == "negative");

    var orientation = "";
    if (!isXNeagtive && !isYNeagtive) {
      orientation = "FrontLeft";
    }
    if (isXNeagtive && !isYNeagtive) {
      orientation = "FrontRight";
    }
    if (!isXNeagtive && isYNeagtive) {
      orientation = "BackLeft";
    }
    if (isXNeagtive && isYNeagtive) {
      orientation = "BackRight";
    }
  
    var measureString = "measResult = CornerMeasure";
    measureString += " " + orientation;
    measureString += " Outside";
    measureString += " xMeasureYOffset=" + xyzFormat.format(cycle.probeClearance);
    measureString += " yMeasureXOffset=" + xyzFormat.format(cycle.probeClearance);
    measureString += " searchDistance=" + xyzFormat.format(cycle.probeClearance);
    measureString += " xMeasureZOffset=" + (z - cycle.depth + tool.diameter / 2);
    measureString += " yMeasureZOffset=" + (z - cycle.depth + tool.diameter / 2);
    measureString += " forceSafeHeight";
    measureString += " skipZMeasure";
    if (probeWCS) {
      measureString += " originXShift=" + xyzFormat.format(-x);
      measureString += " originYShift=" + xyzFormat.format(-y);
      writeBlock(measureString);
    } else {
      measureString += " None";
      writeBlock(measureString);
      expectedArgs = (
        "expectedXPos=" +  xyzFormat.format(x) +
        " expectedYPos=" + xyzFormat.format(y) +
        " measureDirectionX=" + cycle.approach1 +
        " measureDirectionY=" + cycle.approach2
      );
      writeBlock(getProbingArguments(cycle, undefined, expectedArgs));
    }
    break;
  case "probing-x-plane-angle":
    forceXYZ();
    onRapid(x, y, cycle.stock);
    onLinear(x, y, (z - cycle.depth + tool.cornerRadius), cycle.feedrate);
   
    var measureString = "measResult = EdgeMeasureV2 ";
    measureString += (cycle.approach1 == "positive" ? "XPositive" : "XNegative");
    measureString += " searchDistance=" + xyzFormat.format(cycle.probeClearance);
    measureString += " offsetForRotation=" + xyzFormat.format(cycle.probeSpacing);
    measureString += " setRotationOnly=true";
    if (probeWCS) {
      writeBlock(measureString);
    } else {
      measureString += " None";
      writeBlock(measureString);
      expectedArgs = (
        "expectedXPos=" +  xyzFormat.format(x + approach(cycle.approach1) * startPositionOffset) +
        " measureDirectionX=" + (cycle.approach1 == "positive" ? "positive" : "negative")
      );
      writeBlock(getProbingArguments(cycle, undefined, expectedArgs));
    }
    break;
  case "probing-y-plane-angle":
    forceXYZ();
    onRapid(x, y, cycle.stock);
    onLinear(x, y, (z - cycle.depth + tool.cornerRadius), cycle.feedrate);
   
    var measureString = "measResult = EdgeMeasureV2 ";
    measureString += (cycle.approach1 == "positive" ? "YPositive" : "YNegative");
    measureString += " searchDistance=" + xyzFormat.format(cycle.probeClearance);
    measureString += " offsetForRotation=" + xyzFormat.format(cycle.probeSpacing);
    measureString += " setRotationOnly=true";
    if (probeWCS) {
      writeBlock(measureString);
    } else {
      measureString += " None";
      writeBlock(measureString);
      expectedArgs = (
        "expectedYPos=" +  xyzFormat.format(x + approach(cycle.approach1) * startPositionOffset) +
        " measureDirectionY=" + (cycle.approach1 == "positive" ? "positive" : "negative")
      );
      writeBlock(getProbingArguments(cycle, undefined, expectedArgs));
    }
    break;
  default:
    expandCyclePoint(x, y, z);
    return;
  }

  // save probing result in defined wcs
  if (probeWCS && currentSection.workOffset !== null) {
    writeBlock("SaveWcs name=\"" + currentSection.workOffset + "\"");
  }

  return;
}

function getProbingArguments(cycle, probeWorkOffsetCode, additionalArguments) {
  var toolToCompensate;
  var tools = getToolTable();
  if (tools.getNumberOfTools()) {
    for (var i = 0; i < tools.getNumberOfTools(); ++i) {
      var tool = tools.getTool(i);
      if (tool.number == cycle.toolWearNumber) {
        toolToCompensate = tool;
      }
    }
  }
  
  return [
    "ProbeGeometry measResult=measResult",
    (cycle.angleAskewAction == "stop-message" ? "angleTolerance=" + xyzFormat.format(cycle.toleranceAngle ? cycle.toleranceAngle : 0) : undefined),
    ((cycle.updateToolWear && cycle.toolWearErrorCorrection < 100) ? "toolWearErrorCorrection=" + xyzFormat.format(cycle.toolWearErrorCorrection ? cycle.toolWearErrorCorrection / 100 : 100) : undefined),
    (cycle.wrongSizeAction == "stop-message" ? "sizeTolerance=" + xyzFormat.format(cycle.toleranceSize ? cycle.toleranceSize : 0) : undefined),
    (cycle.outOfPositionAction == "stop-message" ? "positionTolerance=" + xyzFormat.format(cycle.tolerancePosition ? cycle.tolerancePosition : 0) : undefined),
    (cycle.updateToolWear ? "toolToUpdateWear=\"" + createToolName(toolToCompensate) + "\"" : undefined),
    ((cycle.updateToolWear && cycleType == "probing-z") ? "Length" : undefined),
    ((cycle.updateToolWear && cycleType !== "probing-z") ? "Diameter" : undefined),
    (cycle.updateToolWear ? "toolUpdateTreshold=" + xyzFormat.format(cycle.toolWearUpdateThreshold ? cycle.toolWearUpdateThreshold : 0) : undefined),
    (cycle.printResults ? "printResults" : undefined), // 1 for advance feature, 2 for reset feature count and advance component number. first reported result in a program should use W2.
    conditional(probeWorkOffsetCode && probeWCS, "S" + probeWorkOffsetCode),
    additionalArguments
  ];
}

function hasProgramProbingOperations() {
  var numberOfSections = getNumberOfSections();
  for (var i = 0; i < numberOfSections; ++i) {
    var section = getSection(i);
    if (isProbeOperation(section)) {
      
      return true;
    }
  }
  return false;
}

function writeProbingProgram() {

  addVariable("enumeration toolWearGeometry (Diameter, Length)");
  addVariable("enumeration direction (positive, negative)");

  addModuleReference("import Math");
  addModuleReference("import ToolChangingUtilities");
  addModuleReference("import ToolParameter");
  addModuleReference("import ToolData");

  // TODO add import Math
  probingProgram = [
    ("program ProbeGeometry("),
    ("  measResult:MeasuringDataWithInfo"),
    ("  optional expectedDimensionX:number"),
    ("  optional expectedDimensionY:number"),
    ("  optional expectedXPos:number"),
    ("  optional expectedYPos:number"),
    ("  optional expectedZPos:number  "),
    ("  optional measureDirectionX:direction   "),
    ("  optional measureDirectionY:direction   "),
    ("  optional toolUpdateTreshold:number"),
    ("  optional toolWearErrorCorrection:number"),
    ("  optional positionTolerance:number    "),
    ("  optional angleTolerance:number"),
    ("  optional sizeTolerance:number"),
    ("  optional toolToUpdateWear:string"),
    ("  optional updateToolWear:toolWearGeometry"),
    ("  optional printResults:boolean)"),
    (""),
    ("  # Tolerance check"),
    ("  if sizeTolerance hasvalue "),
    ("    outOfDimension:boolean"),
    ("    if expectedDimensionX hasvalue"),
    ("        outOfDimension  = Math::Abs(expectedDimensionX - measResult.DimensionX) > sizeTolerance    "),
    ("    endif"),
    ("    if expectedDimensionY hasvalue"),
    ("        outOfDimension  = Math::Abs(expectedDimensionY - measResult.DimensionY) > sizeTolerance "),
    ("    endif"),
    ("    "),
    ("    if outOfDimension"),
    ("        Dialog message=\"Geometrie out of tolerance\" caption=\"Geometrie out of tolerance\" Error"),
    ("    endif"),
    ("  endif"),
    ("  "),
    ("  # Angle check"),
    ("  if angleTolerance hasvalue"),
    ("      if measResult.MeasuredTransformation.RotationZ > angleTolerance"),
    ("         Dialog message=\"Angle out of tolerance\" caption=\"Angle out of tolerance\" Error        "),
    ("      endif"),
    ("  endif"),
    ("  "),
    ("  # Tool wear"),
    ("  if updateToolWear hasvalue and toolToUpdateWear hasvalue"),
    ("     if updateToolWear == toolWearGeometry.Diameter"),
    ("        # get the radius correction from dimension otherwise from position   "),
    ("        radiusCorrection:number"),
    ("        if (expectedDimensionX hasvalue or expectedDimensionY hasvalue)"),
    ("            if (expectedDimensionX hasvalue and expectedDimensionY hasvalue)"),
    ("                radiusCorrection = ("),
    ("                    (expectedDimensionX - measResult.DimensionX) +"),
    ("                    (expectedDimensionX - measResult.DimensionX)) / 4"),
    ("            endif"),
    ("            if (expectedDimensionX hasvalue and not expectedDimensionY hasvalue)"),
    ("                radiusCorrection = (expectedDimensionX - measResult.DimensionX) / 2"),
    ("            endif"),
    ("            if (not expectedDimensionX hasvalue and expectedDimensionY hasvalue)"),
    ("                radiusCorrection = (expectedDimensionY - measResult.DimensionY) / 2"),
    ("            endif          "),
    ("        else       "),
    ("            isXMeasure = expectedXPos hasvalue and measureDirectionX hasvalue"),
    ("            isYMeasure = expectedYPos hasvalue and measureDirectionY hasvalue            "),
    ("            if (isXMeasure or isYMeasure)"),
    ("                if (isXMeasure and not isYMeasure)"),
    ("                    radiusCorrection = (expectedXPos - measResult.MeasuredPosition.X) * GetSignFromDirection(measureDirectionX)"),
    ("                endif"),
    ("                if (isYMeasure and not isXMeasure)"),
    ("                    radiusCorrection = (expectedYPos - measResult.MeasuredPosition.Y) * GetSignFromDirection(measureDirectionY)"),
    ("                endif"),
    ("                if( isXMeasure and isYMeasure)"),
    ("                    radiusCorrection = ("),
    ("                        (expectedXPos - measResult.MeasuredPosition.X) * GetSignFromDirection(measureDirectionX) + "),
    ("                        (expectedYPos - measResult.MeasuredPosition.Y) * GetSignFromDirection(measureDirectionY)                        "),
    ("                    ) / 2                    "),
    ("                endif                        "),
    ("            endif        "),
    ("        endif"),
    ("        "),
    // TODO wenn wear dann ist das so nicht richtig ;-)"),
    ("         toolId = ToolChangingUtilities::GetToolIdFromToolName(toolToUpdateWear)"),
    ("         newDiameter = ToolParameter::GetToolDiameter(toolNumber=toolId) - radiusCorrection * 2"),
    ("         ToolData::SetToolGeometry Diameter=newDiameter toolId=toolId"),
    ("     else"),
    ("        # length correction"),
    ("         "),
    ("     endif"),
    ("  endif   "),
    ("  "),
    ("  # Position"),
    ("  if positionTolerance hasvalue"),
    ("    isOutOfTolerance: boolean"),
    ("    if expectedXPos hasvalue"),
    ("        isOutOfTolerance = Math::Abs(expectedXPos - measResult.MeasuredPosition.X) > positionTolerance        "),
    ("    endif"),
    ("    if expectedYPos hasvalue"),
    ("        isOutOfTolerance = Math::Abs(expectedYPos - measResult.MeasuredPosition.Y) > positionTolerance  "),
    ("    endif"),
    ("    if expectedZPos hasvalue"),
    ("        isOutOfTolerance = Math::Abs(expectedZPos - measResult.MeasuredPosition.Z) > positionTolerance  "),
    ("    endif  "),
    ("    if isOutOfTolerance"),
    ("        Dialog message=\"Position out of tolerance\" caption=\"Position out of tolerance\" Error"),
    ("    endif"),
    ("  endif  "),
    ("endprogram"),
    (""),
    ("function GetSignFromDirection(dir:direction) returns number"),
    ("    if dir == direction.positive"),
    ("        return 1"),
    ("    endif  "),
    ("    return -1    "),
    ("endfunction")
  ];

  probingProgramOperation = {operationProgram: probingProgram.join(EOL)};
  SimPLProgram.operationList.push(probingProgramOperation);
}

// program ProbeGeometry (

//   optional positionTolerance:number
//   optional toolWearErrorCorrection:number
//   optional angleTolerance:number
//   optional sizeTolerance:number
//   optional toolToUpdateWear:string
//   optional updateToolWear:toolWearGeometry
//   printResults:boolean)

function drilling(cycle) {
  var boreCommandString = new Array();
  var depth = xyzFormat.format(cycle.depth);
  
  boreCommandString.push("Drill");
  boreCommandString.push("depth=" + depth);
  boreCommandString.push("strokeRapidZ=" + xyzFormat.format(cycle.clearance - cycle.retract));
  boreCommandString.push("strokeCuttingZ=" + xyzFormat.format(cycle.retract - cycle.stock));
  writeBlock(boreCommandString.join(" "));
}

function chipBreaking(cycle) {
  var boreCommandString = new Array();
  var depth = xyzFormat.format(cycle.depth);
  
  boreCommandString.push("Drill");
  boreCommandString.push("depth=" + depth);
  boreCommandString.push("strokeRapidZ=" + xyzFormat.format(cycle.clearance - cycle.retract));
  boreCommandString.push("strokeCuttingZ=" + xyzFormat.format(cycle.retract - cycle.stock));
  boreCommandString.push("infeedZ=infeedZ");
  writeBlock(boreCommandString.join(" "));
}

function boreMilling(cycle) {
  if (cycle.numberOfSteps > 2) {
    error("Only 2 steps are allowed for bore-milling.");
  }

  var boreCommandString = new Array();
  var depth = xyzFormat.format(cycle.depth);
  boreCommandString.push("DrillMilling");
  boreCommandString.push("diameter=diameter");
  boreCommandString.push("depth=" + depth);
  boreCommandString.push("infeedZ=infeedZ");
  boreCommandString.push("strokeRapidZ=" + xyzFormat.format(cycle.clearance - cycle.retract));
  boreCommandString.push("strokeCuttingZ=" + xyzFormat.format(cycle.retract - cycle.stock));
  
  if (cycle.numberOfSteps == 2) {
    var xycleaning = cycle.stepover;
    var maxzdepthperstep = tool.fluteLength * 0.8;
    boreCommandString.push("finishingXY=" + xyzFormat.format(xycleaning));
    boreCommandString.push("infeedFinishingZ=" + xyzFormat.format(maxzdepthperstep));
  }
  var bottomcleaning = 0;
  // finishingZ = 1;
  writeBlock(boreCommandString.join(" "));
}

function threadMilling(cycle) {
  var threadString = new Array();
  var depth = xyzFormat.format(cycle.depth);

  threadString.push("SpecialThread");
  // threadString.push('threadName=threadName');
  threadString.push("nominalDiameter=nominalDiameter");
  threadString.push("pitch=pitch");
  threadString.push("depth=" + depth);
  threadString.push("strokeRapidZ=" + xyzFormat.format(cycle.clearance - cycle.retract));
  threadString.push("strokeCuttingZ=" + xyzFormat.format(cycle.retract - cycle.stock));
  // threadString.push("threadStandard=threadStandard");
  if (properties.createThreadChamfer) {
    threadString.push("Deburring");
  }
  // ;
  // threadString.push("insideOutside=ThreadMillingSide.Inside");
  threadString.push("finishing=finishing");
  if (cycle.threading == "left") {
    threadString.push("direction=ThreadMillingDirection.LeftHandThread");
  } else {
    threadString.push("direction=ThreadMillingDirection.RightHandThread");
  }
  writeBlock(threadString.join(" "));
}

function tapping(cycle) {
  var tappingString = new Array();
  var depth = xyzFormat.format(cycle.depth);
  tappingString.push("ThreadCutting");
  tappingString.push("pitch=" + xyzFormat.format(tool.threadPitch));
  tappingString.push("depth=" + depth);
  tappingString.push("strokeRapidZ=" + xyzFormat.format(cycle.clearance - cycle.retract));
  tappingString.push("strokeCuttingZ=" + xyzFormat.format(cycle.retract - cycle.stock));
  tappingString.push("threadRpm=" + rpmFormat.format(spindleSpeed));
  if (cycleType == "tapping-with-chip-breaking" || cycleType == "left-tapping-with-chip-breaking" || cycleType == "right-tapping-with-chip-breaking") {
    tappingString.push("breakChipInfeed=" + xyzFormat.format(cycle.incrementalDepth));
  }
  if (tool.type == TOOL_TAP_LEFT_HAND) {
    tappingString.push("direction=ThreadMillingDirection.LeftHandThread");
  } else {
    tappingString.push("direction=ThreadMillingDirection.RightHandThread");
  }
  writeBlock(tappingString.join(" "));
}

function formatCycleTime(cycleTime) {
  // cycleTime = cycleTime + 0.5; // round up
  var seconds = cycleTime % 60 | 0;
  var minutes = ((cycleTime - seconds) / 60 | 0) % 60;
  var hours = (cycleTime - minutes * 60 - seconds) / (60 * 60) | 0;
  if (hours > 0) {
    return subst(localize("%1h:%2m:%3s"), hours, minutes, seconds);
  } else if (minutes > 0) {
    return subst(localize("%1m:%2s"), minutes, seconds);
  } else {
    return subst(localize("%1s"), seconds);
  }
}

function dump(name, _arguments) {
  var result = getCurrentRecordId() + ": " + name + "(";
  for (var i = 0; i < _arguments.length; ++i) {
    if (i > 0) {
      result += ", ";
    }
    if (typeof _arguments[i] == "string") {
      result += "'" + _arguments[i] + "'";
    } else {
      result += _arguments[i];
    }
  }
  result += ")";
  writeln(result);
}

function onSectionEnd() {
  if (typeof inspectionProcessSectionEnd == "function") {
    inspectionProcessSectionEnd();
  }
  writeBlock("ToolCompensation Off");
  writeBlock("PathCorrection Off");

  // reset Z Offset value
  if (properties.useZAxisOffset) {
    writeBlock("ZAxisOffset = 0");
  }

  if (currentSection.isMultiAxis && (properties.rotationAxisSetup != "NONE") && properties.useRtcp) {
    writeBlock("Rtcp Off");
  }

  // adds support for suction
  if (properties.useSuction) {
    writeBlock("Suction Off");
  }

  if (properties.useSequences && !isProbeOperation(currentSection) && !isInspectionOperation(currentSection)) {
    if (!properties.useExternalSequencesFiles) {
      resetWriteRedirection();
    }
    spacingDepth += 1;
  }

  writeBlock("EndBlock");

  spacingDepth -= 1;

  writeBlock("endprogram " + "# " + getOperationName(currentSection));
  resetWriteRedirection();
  SimPLProgram.operationList.push(currentOperation);
  forceAny();
}

function writeBuffer(buffer) {

  if (buffer.length > 0) {
    writeBlock(buffer.join("\r\n") + "\r\n");
    writeBlock("");
    return;
  }

  writeBlock(buffer);
}

function onClose() {
  if (properties.waitAfterOperation) {
    writeWaitProgram();
  }
  spacingDepth = 0;

  // check for additional subprograms
  if (hasProgramInspectionOperations()) {
    writeInspectionProgram();
  }

  // has probing
  if (hasProgramProbingOperations()) {
    writeProbingProgram();
  }

  writeBlock(SimPLProgram.moduleName);
  writeBlock("");
  writeBuffer(SimPLProgram.toolDescriptionList);
  writeBuffer(SimPLProgram.workpieceGeometry);
  writeBuffer(SimPLProgram.sequenceList);
  writeBuffer(SimPLProgram.usingList);
  writeBuffer(SimPLProgram.externalUsermodules);
  writeBuffer(SimPLProgram.globalVariableList);

  finishMainProgram();
  writeBlock(SimPLProgram.mainProgram);
  writeBlock("");

  for (var i = 0; i < SimPLProgram.operationList.length; ++i) {
    writeBlock(SimPLProgram.operationList[i].operationProgram);
  }

  writeBlock("end");

  if (properties.useSequences && !properties.useExternalSequencesFiles) {
    writeComment(spacing);
    writeBlock(sequenceBuffer.toString());
  }
}

// after all the oiperation calls are set close the main program with all the calls
function finishMainProgram() {
  // write the main program footer
  setWriteRedirection(SimPLProgram.mainProgram);
  spacingDepth += 1;

  // write all subprogram calls in the main Program
  for (var i = 0; i < SimPLProgram.operationList.length; ++i) {
    writeBlock(SimPLProgram.operationList[i].operationCall);
  }

  if (properties.writeCoolantCommands) {
    writeBlock("SpraySystem Off");
  }
    
  if (properties.rotationAxisSetup != "NONE" && properties.useRtcp) {
    writeBlock("MultiAxisMode Off");
    writeBlock("Rtcp Off");
  }

  setWorkPlane(new Vector(0, 0, 0)); // reset working plane
  if (properties.useParkPosition) {
    writeBlock("Spindle Off");
    writeBlock("MoveToParkPosition");
  } else {
    writeBlock("MoveToSafetyPosition");
    zOutput.reset();
  }

  spacingDepth -= 1;
  writeBlock("endprogram #" + (programName ? (SP + formatComment(programName)) : "") + ((unit == MM) ? " MM" : " INCH"));
  resetWriteRedirection();
}

// ######################################################################################################################
// ######################################################################################################################
// ######################################################################################################################
// ######################################################################################################################

// code for inspection support
properties.singleResultsFile = true; // create a single file containing the results for all posted inspection toolpath
properties.useDirectConnection = false; // determines whether the inspection results are writen to a file or read directly into Fusion
properties.controlConnectorVersion = 1; // control connector version
properties.toolOffsetType = "geomOnly";
properties.commissioningMode = true; // Enables commissioning mode where M0 and messages are output at key points in the program
properties.stopOnInspectionEnd = true; // Output M0 after each inspection section to retrieve results
if (propertyDefinitions === undefined) {
  propertyDefinitions = {};
}

propertyDefinitions.singleResultsFile = {title: "Create Single Results File", description: "Set to false if you want to store the measurement results for each inspection toolpath in a seperate file", group: 0, type: "boolean"};
propertyDefinitions.useDirectConnection = {title: "Stream Measured Point Data", description: "Set to true to stream inspection results", group: 0, type: "boolean"};
propertyDefinitions.controlConnectorVersion = {title: "Results connector version", description: "Interface version for direct connection to read inspection results", group: 0, type: "integer"};
propertyDefinitions.toolOffsetType = {
  title: "Tool offset type",
  description: "Select the which offsets are available on the tool offset page",
  group: 0,
  type: "enum",
  values: [
    {id: "geomWear", title: "Geometry & Wear"},
    {id: "geomOnly", title: "Geometry only"}
  ]
};
propertyDefinitions.commissioningMode = {title: "Inspection Commissioning Mode", description: "Enables commissioning mode where M0 and messages are output at key points in the program", group: 0, type: "boolean"};
propertyDefinitions.stopOnInspectionEnd = {title: "Stop on Inspection End", description: "Set to ON to output M0 at the end of each inspection toolpath", group: 0, type: "boolean"};

var ijkInspectionFormat = createFormat({decimals:5, forceDecimal:true});
// inspection variables
var inspectionVariables = {
  localVariablePrefix: "#",
  probeRadius: 0,
  pointNumber: 1,
 
  inspectionSections: 0,
  inspectionSectionCount: 0,
  workpieceOffset: "",
};

var macroFormat = createFormat({prefix:inspectionVariables.localVariablePrefix, decimals:0});

// function inspectionWriteVariables() {
//   // loop through all NC stream sections to check for surface inspection
//   for (var i = 0; i < getNumberOfSections(); ++i) {
//     var section = getSection(i);
//     if (isInspectionOperation(section)) {
//       if (inspectionVariables.inspectionSections == 0) {
//         if (properties.commissioningMode) {
//           //sequence numbers cannot be active while commissioning mode is on
//           properties.showSequenceNumbers = false;
//         }
//         inspectionVariables.workpieceOffset = section.workOffset;
//         var count = 1;
//         var localVar = properties.probeLocalVar;
//         var prefix = inspectionVariables.localVariablePrefix;
//         inspectionVariables.probeRadius = prefix + count;
//         inspectionVariables.xTarget = prefix + ++count;
//         inspectionVariables.yTarget = prefix + ++count;
//         inspectionVariables.zTarget = prefix + ++count;
//         inspectionVariables.xMeasured = prefix + ++count;
//         inspectionVariables.yMeasured = prefix + ++count;
//         inspectionVariables.zMeasured = prefix + ++count;
//         inspectionVariables.activeToolLength = prefix + ++count;
//         inspectionVariables.macroVariable1 = prefix + ++count;
//         inspectionVariables.macroVariable2 = prefix + ++count;
//         inspectionVariables.macroVariable3 = prefix + ++count;
//         inspectionVariables.macroVariable4 = prefix + ++count;
      
//         inspectionValidateInspectionSettings();
//         // //inspectionVariables.probeResultsReadPointer = prefix + (properties.probeResultsBuffer + 2);
//         // inspectionVariables.probeResultsWritePointer = prefix + (properties.probeResultsBuffer + 3);
//         // inspectionVariables.probeResultsCollectionActive = prefix + (properties.probeResultsBuffer + 4);
//         // inspectionVariables.probeResultsStartAddress = properties.probeResultsBuffer + 5;
//         if (properties.toolOffsetType == "geomOnly") {
//           inspectionVariables.systemVariableOffsetLengthTable = "2000";
//         }
//         if (properties.commissioningMode) {
//           writeBlock("#3006=1(Inspection commissioning mode active,see post properties)");
//         }
//         if (properties.useDirectConnection) {
//           // check to make sure local variables used in results buffer and inspection do not clash
//           var localStart = properties.probeLocalVar;
//           var localEnd = count;
//           var bufferStart = properties.probeResultsBuffer;
//           var bufferEnd = properties.probeResultsBuffer + ((3 * properties.probeNumberofPoints) + 8);
//           if ((localStart >= bufferStart && localStart <= bufferEnd) ||
//             (localEnd >= bufferStart && localEnd <= bufferEnd)) {
//             error("Local variables defined (" + prefix + localStart + "-" + prefix + localEnd +
//               ") and live probe results storage area (" + prefix + bufferStart + "-" + prefix + bufferEnd + ") overlap."
//             );
//           }
//           writeBlock(macroFormat.format(properties.probeResultsBuffer) + " = " + properties.controlConnectorVersion);
//           writeBlock(macroFormat.format(properties.probeResultsBuffer + 1) + " = " + properties.probeNumberofPoints);
//           writeBlock(inspectionVariables.probeResultsReadPointer + " = 0");
//           writeBlock(inspectionVariables.probeResultsWritePointer + " = 1");
//           writeBlock(inspectionVariables.probeResultsCollectionActive + " = 0");
//           if (properties.probeResultultsBuffer == 0) {
//             error("Probe Results Buffer start address cannot be zero when using a direct connection.");
//           }
//           inspectionWriteFusionConnectorInterface("HEADER");
//         }
//       }
//       inspectionVariables.inspectionSections += 1;
//     }
//   }
// }

// adds the necessary references for inspection to the program header
function addInspectionReferences() {
  if (hasProgramInspectionOperations()) {
    SimPLProgram.usingList.push("using File, LinearAlgebra, LinearAlgebraHelper, MeasuringCyclesExecutor, XyzSensor, String");
    SimPLProgram.usingList.push("import AxisSystem");
  }
}

function hasProgramInspectionOperations() {
  var numberOfSections = getNumberOfSections();
  for (var i = 0; i < numberOfSections; ++i) {
    var section = getSection(i);
    if (isInspectionOperation(section)) {
      
      return true;
    }
  }
  return false;
}

function inspectionValidateInspectionSettings() {
  var errorText = "";
  if (errorText != "") {
    error(localize("The following properties need to be configured:" + errorText + "\n-Please visit https://forums.autodesk.com/t5/hsm-post-processor-forum/bd-p/218 for more information-"));
  }
}

function onProbe(status) {
  if (status) {// probeON
    writeBlock("PrepareXyzSensor"); // Command for switching the probe on
  } else { // probe OFF
    writeBlock("UnprepareXyzSensor"); // Command for switching the probe off
  }
}

// convert the hsm vector to the datron simpl position initilizer.
function vectorToDatronPosString(vec) {
  return "NewPos(" + xyzFormat.format(vec.x) + ", " + xyzFormat.format(vec.y) + ", " + xyzFormat.format(vec.z) + ")";
}

function inspectionCycleInspect(cycle, epx, epy, epz) {
  if (getNumberOfCyclePoints() != 3) {
    error(localize("Missing Endpoint in Inspection Cycle, check Approach and Retract heights"));
  }
  
  if (!isLastCyclePoint()) {
    return;
  }

  forceFeed(); // ensure feed is always output - just incase.
  if (currentSection.isMultiAxis()) {
    error("MultiAxisNot Supportetd");
  }
  var f;

  var m = getRotation();
  var v = new Vector(cycle.nominalX, cycle.nominalY, cycle.nominalZ);
  var targetPoint = m.multiply(v);
  var pathVector = new Vector(cycle.nominalI, cycle.nominalJ, cycle.nominalK);
  var measureDirection = m.multiply(pathVector).normalized.getNegated();
  var searchDistance = cycle.probeClearance;
  
  //call inspection subprogram
  writeBlock("MeasurePoint(");
  spacingDepth += 1;
  writeBlock("pointID=" + cycle.pointID);
  writeBlock("surfacePos=" + vectorToDatronPosString(targetPoint));
  writeBlock("measureDirection=" + vectorToDatronPosString(measureDirection));
  writeBlock("searchDistance=" + xyzFormat.format(searchDistance));
  writeBlock("surfaceOffset=" + xyzFormat.format(getParameter("operation:inspectSurfaceOffset")));
  writeBlock("upper=" + xyzFormat.format(getParameter("operation:inspectUpperTolerance")));
  writeBlock("lower=" + xyzFormat.format(getParameter("operation:inspectLowerTolerance")) + ")");
  spacingDepth -= 1;
  writeBlock("");
  zOutput.reset();
}

// create the subprogram that makes the inspection probing  and the output to the result file.
function writeInspectionProgram() {
  // Not triggered is captured by the NEXT Control
  inspectProgram = new Array();

  inspectProgram.push("program MeasurePoint pointID:number surfacePos:Position measureDirection:Position searchDistance:number surfaceOffset:number upper:number lower:number\r\n");
  inspectProgram.push("\t\r\n");
  inspectProgram.push("\t# measure\r\n");
  inspectProgram.push("\tmeasureResult = GetMeasuringResultCompensation(\r\n");
  inspectProgram.push("\t\tArrangeMeasuring(\r\n");
  inspectProgram.push("\t\t\ttargetPosition=surfacePos\r\n");
  inspectProgram.push("\t\t\tdirection=measureDirection\r\n");
  inspectProgram.push("\t\t\tdistance=searchDistance),\r\n");
  inspectProgram.push("\t\t AxisSystem::GetRcsMatrix)\r\n");
  inspectProgram.push("\t\t\r\n");

  inspectProgram.push("\t# Trigger not found \r\n");
  inspectProgram.push("\tif  measureResult.active == false\r\n");
  inspectProgram.push("\t\tDialog message=\"Target Point not found\" caption=\"Inspection error\" Error\r\n");
  inspectProgram.push("\tendif\r\n");
  inspectProgram.push("\r\n");
  
  inspectProgram.push("\t# write nominal values\r\n");
  inspectProgram.push("\tmeasureNominalString = StringFormat(\r\n");
  inspectProgram.push("\t\tbaseString=\"G800 N{0} X{1:f3} Y{2:f3} Z{3:f3} I{4:f3} J{5:f3} K{6:f3} O{7:f5} U{8:f3} L{9:f3}\"\r\n");
  inspectProgram.push("\t\tp0=pointID  \r\n");
  inspectProgram.push("\t\tp1=surfacePos.X\r\n");
  inspectProgram.push("\t\tp2=surfacePos.Y\r\n");
  inspectProgram.push("\t\tp3=surfacePos.Z\r\n");
  inspectProgram.push("\t\tp4=measureDirection.X * -1\r\n");
  inspectProgram.push("\t\tp5=measureDirection.Y * -1\r\n");
  inspectProgram.push("\t\tp6=measureDirection.Z * -1\r\n");
  inspectProgram.push("\t\tp7=surfaceOffset\r\n");
  inspectProgram.push("\t\tp8=upper\r\n");
  inspectProgram.push("\t\tp9=lower)  \r\n");
  inspectProgram.push("\tmeasureNominalString = StringReplace(measureNominalString, \",\", \".\")        \r\n");
  inspectProgram.push("\tFileWriteLine filename=InspectionFilename value=measureNominalString\r\n");
  inspectProgram.push("\t\r\n");

  inspectProgram.push("\t# write result values\r\n");
  inspectProgram.push("\tmeasureResultString = StringFormat(\r\n");
  inspectProgram.push("\t\tbaseString=\"G801 N{0} X{1:f3} Y{2:f3} Z{3:f3} R{4:f3}\"\r\n");
  inspectProgram.push("\t\tp0=pointID\r\n");
  inspectProgram.push("\t\tp1=measureResult.measuredPoint.X\r\n");
  inspectProgram.push("\t\tp2=measureResult.measuredPoint.Y\r\n");
  inspectProgram.push("\t\tp3=measureResult.measuredPoint.Z\r\n");
  inspectProgram.push("\t\tp4=GetProbeTipRadius())\r\n");
  inspectProgram.push("\tmeasureResultString = StringReplace(measureResultString, \",\", \".\")\r\n");
  inspectProgram.push("\r\n");
  inspectProgram.push("\tFileWriteLine filename=InspectionFilename value=measureResultString\r\n");
  inspectProgram.push("\t\r\n");

  inspectProgram.push("\t# check result\r\n");
  inspectProgram.push("\tmeasuredPosition = NewPos(\r\n");
  inspectProgram.push("\t\tmeasureResult.measuredPoint.X,\r\n");
  inspectProgram.push("\t\tmeasureResult.measuredPoint.Y,\r\n");
  inspectProgram.push("\t\tmeasureResult.measuredPoint.Z)\r\n");
  inspectProgram.push("\t\r\n");
  inspectProgram.push("\tmeasuredDifferenceVector = SubPosition(surfacePos, measuredPosition)\r\n");
  inspectProgram.push("\tdeltaDirection = Normalize(measuredDifferenceVector)\r\n");
  inspectProgram.push("\tdistance = GetPositionDistance(measuredDifferenceVector)\r\n");
  inspectProgram.push("\t\r\n");
  inspectProgram.push("\t# check deviation direction\r\n");
  inspectProgram.push("\tif(GetPositionDistance(SubPosition(Normalize(measuredDifferenceVector),measureDirection))>1)\r\n");
  inspectProgram.push("\t\tdistance = distance * -1\r\n");
  inspectProgram.push("\tendif\r\n");
  inspectProgram.push("\t\r\n");
  inspectProgram.push("\tif(distance > lower and distance < upper)\r\n");
  inspectProgram.push("\t\treturn\r\n");
  inspectProgram.push("\tendif\r\n");
  inspectProgram.push("\t  \r\n");

  inspectProgram.push("\t# Position out of tolerance\r\n");
  inspectProgram.push("\tDialog message=\"Position out of tolerance\" caption=\"Position out of tolerance\" Error\r\n");
  inspectProgram.push("\r\n");

  inspectProgram.push("endprogram\r\n");

  inspectProgramOperation = {operationProgram: inspectProgram};

  SimPLProgram.operationList.push(inspectProgramOperation);
}

// function inspectionWriteFusionConnectorInterface(ncSection) {
//   if (ncSection == "MEASURE") {
//     writeBlock("IF " + inspectionVariables.probeResultsCollectionActive + " NE 1 GOTO " + inspectionVariables.pointNumber);
//     writeBlock("WHILE [" + inspectionVariables.probeResultsReadPointer + " EQ " + inspectionVariables.probeResultsWritePointer + "] DO 1");
//     onDwell(0.5);
//     writeComment("WAITING FOR FUSION CONNECTION");
//     writeBlock("G53");
//     writeBlock("END 1");
//     writeBlock("N" + inspectionVariables.pointNumber);
//   } else {
//     writeBlock("WHILE [" + inspectionVariables.probeResultsCollectionActive + " NE 1] DO 1");
//     onDwell(0.5);
//     writeComment("WAITING FOR FUSION CONNECTION");
//     writeBlock("G53");
//     writeBlock("END 1");
//   }
// }

function inspectionProcessSectionStart() {
  // only write header once if user selects a single results file
  if (inspectionVariables.inspectionSectionCount == 0 || !properties.singleResultsFile || (currentSection.workOffset != inspectionVariables.workpieceOffset)) {
    inspectionCreateResultsFileHeader();
  }
  inspectionVariables.inspectionSectionCount += 1;
  // write the toolpath name as a comment
  writeBlock("FileWriteLine filename=InspectionFilename value=\";TOOLPATH " + getParameter("operation-comment") + "\"");
  inspectionWriteWorkplaneTransform();
  if (properties.toolOffsetType == "geomOnly") {
    writeComment("Geometry Only");
    // TODO fill
  } else {
    writeComment("Geometry and Wear");
    // TODO fill
  }
}

function getInspectionFilename() {
  var resFile;
  if (properties.singleResultsFile) {
    resFile = getParameter("job-description") + " RESULTS";
  } else {
    resFile = getParameter("operation-comment") + " RESULTS";
  }
  
  resFile = resFile.replace(/[^a-zA-Z0-9_ ]/g, "");
  resFile += ".txt";
  return resFile;
}

// add a varibale to the global declarations
function addVariable(value) {
  if (SimPLProgram.globalVariableList.indexOf(value) == -1) {
    SimPLProgram.globalVariableList.push(value);
  }
}
// add a varibale to the global declarations
function addModuleReference(value) {
  if (SimPLProgram.usingList.indexOf(value) == -1) {
    SimPLProgram.usingList.push(value);
  }
}

function inspectionCreateResultsFileHeader() {
  // Add the filename to the global variables declarations
  addVariable("InspectionFilename:string");

  writeBlock("InspectionFilename = \"" + getInspectionFilename() + "\"");
  writeComment("delete existing old file");
  writeBlock("if FileExists filename=InspectionFilename");
  writeBlock("\tFileDelete filename=InspectionFilename");
  writeBlock("endif");

  writeBlock("");
  if (inspectionVariables.inspectionSectionCount == 0 || !properties.singleResultsFile) {
    writeBlock("FileWriteLine filename=InspectionFilename value=\"START\"");
    if (hasGlobalParameter("document-id")) {
      writeBlock("FileWriteLine filename=InspectionFilename value=\"DOCUMENTID " + getGlobalParameter("document-id") + "\"");
    }
    if (hasGlobalParameter("model-version")) {
      writeBlock("FileWriteLine filename=InspectionFilename value=\"MODELVERSION " + getGlobalParameter("model-version") + "\"");
    }
  }
  // write the toolpath id in the results file
  writeBlock("FileWriteLine filename=InspectionFilename value=\"TOOLPATHID " + getParameter("autodeskcam:operation-id") + "\"");
  inspectionWriteCADTransform();
  inspectionVariables.workpieceOffset = currentSection.workOffset;
}

function inspectionWriteCADTransform() {
  var cadOrigin = currentSection.getModelOrigin();
  var cadWorkPlane = currentSection.getModelPlane().getTransposed();
  var cadEuler = cadWorkPlane.getEuler2(EULER_XYZ_S);
  writeBlock(
    "FileWriteLine filename=InspectionFilename value=\"G331" +
    " N" + inspectionVariables.pointNumber +
    " A" + abcFormat.format(cadEuler.x) +
    " B" + abcFormat.format(cadEuler.y) +
    " C" + abcFormat.format(cadEuler.z) +
    " X" + xyzFormat.format(-cadOrigin.x) +
    " Y" + xyzFormat.format(-cadOrigin.y) +
    " Z" + xyzFormat.format(-cadOrigin.z) +
    "\""
  );
}

function inspectionWriteWorkplaneTransform() {
  var euler = currentSection.workPlane.getEuler2(EULER_XYZ_S);
  var abc = new Vector(euler.x, euler.y, euler.z);
  writeBlock("FileWriteLine filename=InspectionFilename value=\"G330" +
    " N" + inspectionVariables.pointNumber +
    " A" + abcFormat.format(abc.x) +
    " B" + abcFormat.format(abc.y) +
    " C" + abcFormat.format(abc.z) +
    " X0 Y0 Z0 I0 R0\""
  );
}

function inspectionProcessSectionEnd() {
  if (isInspectionOperation(currentSection)) {
    // close inspection results file if the NC has inspection toolpaths
    if ((!properties.singleResultsFile) || (inspectionVariables.inspectionSectionCount == inspectionVariables.inspectionSections)) {
 
      // TODO comisioning mode einfügen
    }
    writeBlock("FileWriteLine filename=InspectionFilename value=\"END\"");
    writeBlock(properties.stopOnInspectionEnd == true ? "Dialog message=\"Finish Inspection\" Yes No caption=\"Inspection\" Info" : "");
  }
}
