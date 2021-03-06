CREATE DATABASE winetestbot DEFAULT CHARSET=utf8 DEFAULT COLLATE=utf8_bin;

USE winetestbot;

CREATE TABLE Users
(
  Name      VARCHAR(40)     NOT NULL,
  EMail     VARCHAR(40)     NOT NULL,
  Password  CHAR(49)        NOT NULL,
  Active    ENUM('Y', 'N')  NOT NULL,
  RealName  VARCHAR(40)     NULL,
  ResetCode CHAR(32)        NULL,
  PRIMARY KEY(Name)
)
ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE Roles
(
  Name          VARCHAR(20)    NOT NULL,
  IsDefaultRole ENUM('Y', 'N') NOT NULL,
  PRIMARY KEY(Name)
)
ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE UserRoles
(
  UserName VARCHAR(40) NOT NULL,
  RoleName VARCHAR(20) NOT NULL,
  PRIMARY KEY (UserName, RoleName),
  FOREIGN KEY (UserName) REFERENCES Users(Name),
  FOREIGN KEY (RoleName) REFERENCES Roles(Name)
)
ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE Sessions
(
  Id        CHAR(32)        NOT NULL,
  UserName  VARCHAR(40)     NOT NULL,
  Permanent ENUM('Y', 'N')  NOT NULL,
  PRIMARY KEY (Id),
  FOREIGN KEY (UserName) REFERENCES Users(Name)
)
ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE VMs
(
  Name         VARCHAR(20)      NOT NULL,
  Type         ENUM('base', 'extra', 'build', 'retired') NOT NULL,
  SortOrder    INT(3)           NOT NULL,
  Bits         ENUM('32', '64') NOT NULL,
  Status       ENUM('reverting', 'sleeping', 'idle', 'running', 'dirty', 'offline') NOT NULL,
  VmxHost      VARCHAR(64)      NULL,
  VmxFilePath  VARCHAR(64)      NOT NULL,
  IdleSnapshot VARCHAR(32)      NOT NULL,
  Interactive  ENUM('Y', 'N')   NOT NULL,
  Description  VARCHAR(40)      NULL,
  PRIMARY KEY (Name)
)
ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE Patches
(
  Id          INT(7)          NOT NULL,
  Received    DATETIME        NOT NULL,
  Disposition VARCHAR(40)     NOT NULL,
  AffectsTests ENUM('Y', 'N') NOT NULL
  FromName    VARCHAR(40)     NULL,
  FromEMail   VARCHAR(40)     NULL,
  Subject     VARCHAR(120)    NULL,
  PRIMARY KEY (Id)
)
ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE PendingPatchSets
(
  EMail      VARCHAR(40) NOT NULL,
  TotalParts INT(2)      NOT NULL,
  PRIMARY KEY (EMail, TotalParts)
)
ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE PendingPatches
(
  PendingPatchSetEMail      VARCHAR(40) NOT NULL,
  PendingPatchSetTotalParts INT(2)      NOT NULL,
  No                        INT(2)      NOT NULL,
  PatchId                   INT(7)      NOT NULL,
  FOREIGN KEY (PendingPatchSetEMail, PendingPatchSetTotalParts)
          REFERENCES PendingPatchSets(EMail, TotalParts),
  FOREIGN KEY (PatchId) REFERENCES Patches(Id),
  PRIMARY KEY (PendingPatchSetEMail, PendingPatchSetTotalParts, No)
)
ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE Branches
(
  Name      VARCHAR(20)     NOT NULL,
  IsDefault ENUM('Y', 'N')  NOT NULL,
  PRIMARY KEY(Name)
)
ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE Jobs
(
  Id         INT(5)      NOT NULL AUTO_INCREMENT,
  Archived   ENUM('Y', 'N') NOT NULL,
  BranchName VARCHAR(20) NOT NULL,
  UserName   VARCHAR(40) NOT NULL,
  Priority   INT(1)      NOT NULL,
  Status     ENUM('queued', 'running', 'completed', 'failed') NOT NULL,
  Remarks    VARCHAR(50) NULL,
  Submitted  DATETIME    NULL,
  Ended      DATETIME    NULL,
  PatchId    INT(7)      NULL,
  FOREIGN KEY (BranchName) REFERENCES Branches(Name),
  FOREIGN KEY (UserName) REFERENCES Users(Name),
  FOREIGN KEY (PatchId) REFERENCES Patches(Id),
  PRIMARY KEY (Id),
  INDEX JobsArchived (Archived)
)
ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE Steps
(
  JobId                 INT(5) NOT NULL,
  No                    INT(2) NOT NULL,
  Type                  ENUM('suite', 'single', 'build', 'reconfig') NOT NULL,
  Status                ENUM('queued', 'running', 'completed', 'failed', 'skipped') NOT NULL,
  FileName              VARCHAR(100) NOT NULL,
  FileType              ENUM('exe32', 'exe64', 'patchdlls', 'patchprograms', 'dll32', 'dll64', 'zip') NOT NULL,
  InStaging             ENUM('Y', 'N') NOT NULL,
  DebugLevel            INT(2) NOT NULL,
  ReportSuccessfulTests ENUM('Y', 'N') NOT NULL,
  PRIMARY KEY (JobId, No),
  FOREIGN KEY (JobId) REFERENCES Jobs(Id)
)
ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE Tasks
(
  JobId        INT(5) NOT NULL,
  StepNo       INT(2) NOT NULL,
  No           INT(2) NOT NULL,
  Status       ENUM('queued', 'running', 'completed', 'failed', 'skipped') NOT NULL,
  VMName       VARCHAR(20) NOT NULL,
  Timeout      INT(4) NOT NULL,
  CmdLineArg   VARCHAR(256) NULL,
  ChildPid     INT(5) NULL,
  Started      DATETIME NULL,
  Ended        DATETIME NULL,
  TestFailures INT(6) NULL,
  PRIMARY KEY (JobId, StepNo, No),
  FOREIGN KEY(VMName) REFERENCES VMs(Name)
)
ENGINE=InnoDB DEFAULT CHARSET=utf8;

INSERT INTO Roles (Name, IsDefaultRole) VALUES('admin', 'N');
INSERT INTO Roles (Name, IsDefaultRole) VALUES('wine-devel', 'Y');

INSERT INTO Users (Name, EMail, Password, Active, RealName)
       VALUES('batch', '/dev/null', '*', 'Batch user for internal jobs', NULL);

INSERT INTO Branches (Name, IsDefault) VALUES('master', 'Y');
