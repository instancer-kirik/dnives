module dcore.imports;

// Standard library imports
public import std.stdio;
public import std.string;
public import std.file;
public import std.path;
public import std.datetime;
public import std.json;
public import std.exception;
public import std.algorithm;
public import std.array;
public import std.format;
public import std.variant;
public import std.regex;
public import core.time;

// dlangui imports
public import dlangui;
public import dlangui.core.logger;
public import dlangui.platforms.common.platform;
public import dlangui.widgets.widget;
public import dlangui.widgets.menu;
public import dlangui.widgets.tabs;
public import dlangui.widgets.layouts;
public import dlangui.widgets.docks;
public import dlangui.widgets.editors;
public import dlangui.widgets.controls;
public import dlangui.widgets.statusline;
public import dlangui.widgets.toolbars;
public import dlangui.dialogs.filedlg;
public import dlangui.dialogs.dialog;
public import dlangui.dml.parser;

// Core component imports 
public import dcore.components.cccore;
public import dcore.vaultmanager;
public import dcore.config;
public import dcore.ui.mainwindow;