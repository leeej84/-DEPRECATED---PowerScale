
var ctxLine = document.getElementById("myLine");
var ctxLineCPU = document.getElementById("myLineCPU");
var ctxLineMEM = document.getElementById("myLineMemory");
var ctxLineIND = document.getElementById("myLineIndex");
var ctxLineSESS = document.getElementById("myLineSession");

var myLineChart = new Chart(ctxLine, {
      "type":  "line",
    "data":  <TIMESJSON>,
                 "datasets":  [
                                  {
                                      "label":  "Machines On",
                                      "borderColor":  "#FFB266",
                                      <MACHINESONDATA>,
                                      "fill":  "false"
                                  },
                                  {
                                      "label":  "Machines Maintenace",
                                      "borderColor":  "#004C99",
                                      <MACHINESMAINTDATA>,
                                      "fill":  "false"
                                  },
								  {
                                      "label":  "Machines Excluded",
                                      "borderColor":  "#3E751D",
                                      <MACHINESEXCLDATA>,
                                      "fill":  "false"
                                  },
								  {
                                      "label":  "Machines Scaled",
                                      "borderColor":  "#FFFF33",
                                      <MACHINESSCALEDATA>,
                                      "fill":  "false"
                                  }
                              ]
             }
});

var myLineChart2 = new Chart(ctxLineCPU, {
      "type":  "line",
    "data":  <TIMESJSON>,
                 "datasets":  [
                                  {
                                      "label":  "CPU",
                                      "borderColor":  "#FF0000",
                                      <CPUDATA>,
                                      "fill":  "false"
                                  }
                              ]
             }
});

var myLineChart2 = new Chart(ctxLineMEM, {
      "type":  "line",
    "data":  <TIMESJSON>,
                 "datasets":  [
                                  {
                                      "label":  "Memory",
                                      "borderColor":  "#009900",
                                      <MEMORYDATA>,
                                      "fill":  "false"
                                  }
                              ]
             }
});

var myLineChart2 = new Chart(ctxLineIND, {
      "type":  "line",
    "data":  <TIMESJSON>,
                 "datasets":  [
                                  {
                                      "label":  "Load Index",
                                      "borderColor":  "#9999FF",
                                      <INDEXDATA>,
                                      "fill":  "false"
                                  }
                                  ]
             }
});

var myLineChart2 = new Chart(ctxLineSESS, {
      "type":  "line",
    "data":  <TIMESJSON>,
                 "datasets":  [
                                  {
                                      "label":  "Session",
                                      "borderColor":  "#FF007F",
                                      <SESSIONDATA>,
                                      "fill":  "false"
                                  }
                              ]
             }
});