//Pragma
#pragma semicolon 1
#pragma newdecls required

//Defines
//#define DEBUG
#define PLUGIN_DESCRIPTION "Automatically takes custom files and precaches them and adds them to the downloads table."
#define PLUGIN_VERSION "1.0.4"

//Sourcemod Includes
#include <sourcemod>
#include <sdktools>

//Globals
ConVar cvar_Status;
ConVar cvar_Exclusions;

ArrayList array_Exclusions;
ArrayList array_Downloadables;

enum eLoad
{
	Load_Materials,
	Load_Models,
	Load_Sounds,
	Load_Particles
}

public Plugin myinfo =
{
	name = "[ANY] Auto File Loader",
	author = "Drixevel",
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = "https://drixevel.dev/"
};

public void OnPluginStart()
{
	LoadTranslations("common.phrases");

	CreateConVar("sm_autofileloader_version", PLUGIN_VERSION, PLUGIN_DESCRIPTION, FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_SPONLY | FCVAR_DONTRECORD);
	cvar_Status = CreateConVar("sm_autofileloader_status", "1", "Status of the plugin.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	cvar_Exclusions = CreateConVar("sm_autofileloader_exclusions_file", "configs/afl_exclusions.cfg", "File location to use for the exclusions config.", FCVAR_NOTIFY);

	AutoExecConfig();

	array_Exclusions = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));

	array_Downloadables = new ArrayList(ByteCountToCells(6));
	array_Downloadables.PushString(".vmt");
	array_Downloadables.PushString(".vtf");
	array_Downloadables.PushString(".vtx");
	array_Downloadables.PushString(".mdl");
	array_Downloadables.PushString(".phy");
	array_Downloadables.PushString(".vvd");
	array_Downloadables.PushString(".wav");
	array_Downloadables.PushString(".mp3");
	array_Downloadables.PushString(".pcf");

	RegAdminCmd("sm_glist", Command_GenerateList, ADMFLAG_ROOT);
}

public void OnMapStart()
{
	if (!cvar_Status.BoolValue)
	{
		return;
	}

	PullExclusions();
}

public Action Command_GenerateList(int client, int args)
{
	StartProcess(true);
	ReplyToCommand(client, "Generated, file should be under 'addons/sourcemod/logs/autofileloader.list.log'.");
	return Plugin_Handled;
}

void PullExclusions()
{
	//Lets handle the excludions.
	char sExclusionPath[PLATFORM_MAX_PATH];
	cvar_Exclusions.GetString(sExclusionPath, sizeof(sExclusionPath));

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), sExclusionPath);

	KeyValues kv = new KeyValues("autofileloader_exclusions");
	
	//Clear the exclusions preemptively to make sure that if we cleared out the config, it stays put.
	array_Exclusions.Clear();
	
	//If this returns not found or empty, the file is empty so we don't do anything.
	if (kv.ImportFromFile(sPath) && kv.GotoFirstSubKey(false))
	{
		char sEnabled[3]; char sExclude[PLATFORM_MAX_PATH];
		do
		{
			//The key is kind of pointless so we make it had a meaning by making it a status for enabled or disabled.
			kv.GetSectionName(sEnabled, sizeof(sEnabled));

			if (StringToInt(sEnabled) > 0)
			{
				kv.GetString(NULL_STRING, sExclude, sizeof(sExclude));

				if (strlen(sExclude) > 0)
				{
					array_Exclusions.PushString(sExclude);
				}
			}
		}
		while(kv.GotoNextKey());
	}
	else
	{
		//Config doesn't exist, lets create it.
		kv.ExportToFile(sPath);
	}

	delete kv;
	LogMessage("Exclusions parsed successfully.");
	
	//Make sure the exclusions are taken care of first.
	StartProcess();
}

void StartProcess(bool print = false)
{
	//Load the base directory's files.
	AutoLoadDirectory(".", print);

	//Load all the folders inside of the custom folder and load their files.
	DirectoryListing dir = OpenDirectory("custom");
	if (dir != null)
	{
		FileType fType;
		char sPath[PLATFORM_MAX_PATH];

		while (dir.GetNext(sPath, sizeof(sPath), fType))
		{
			//We only need to parse through directories here.
			if (fType != FileType_Directory)
			{
				continue;
			}

			//Exclude these paths since they're invalid.
			if (StrEqual(sPath, "workshop") || StrEqual(sPath, ".") || StrEqual(sPath, ".."))
			{
				continue;
			}

			char sBuffer[PLATFORM_MAX_PATH];
			Format(sBuffer, sizeof(sBuffer), "custom/%s", sPath);

			AutoLoadDirectory(sBuffer, print);
		}

		delete dir;
	}
}

bool AutoLoadDirectory(const char[] path, bool print = false)
{	
	DirectoryListing dir = OpenDirectory(path);

	if (dir == null)
	{
		return false;
	}

	char sPath[PLATFORM_MAX_PATH];
	FileType fType;

	while (dir.GetNext(sPath, sizeof(sPath), fType))
	{
		//We only need to parse through directories here.
		if (fType != FileType_Directory)
		{
			continue;
		}
		
		char sBuffer[PLATFORM_MAX_PATH];
		Format(sBuffer, sizeof(sBuffer), "%s/%s", path, sPath);

		if (StrEqual(sPath, "materials"))
		{
			AutoLoadFiles(sBuffer, Load_Materials, print);
		}
		else if (StrEqual(sPath, "models"))
		{
			AutoLoadFiles(sBuffer, Load_Models, print);
		}
		else if (StrEqual(sPath, "sound"))
		{
			AutoLoadFiles(sBuffer, Load_Sounds, print);
		}
		else if (StrEqual(sPath, "particles"))
		{
			AutoLoadFiles(sBuffer, Load_Particles, print);
		}
	}

	delete dir;
	return true;
}

bool AutoLoadFiles(const char[] path, eLoad load, bool print = false)
{
	#if defined DEBUG
	LogToFileEx("addons/sourcemod/logs/autofileloader.debug.log", "Loading Directory: %s - %i", path, load);
	#endif
	
	DirectoryListing dir = OpenDirectory(path);

	if (dir == null)
	{
		return false;
	}

	char sPath[PLATFORM_MAX_PATH];
	FileType fType;

	while (dir.GetNext(sPath, sizeof(sPath), fType))
	{
		//Exclude these paths since they're invalid.
		if (StrEqual(sPath, ".") || StrEqual(sPath, ".."))
		{
			continue;
		}

		char sBuffer[PLATFORM_MAX_PATH];
		Format(sBuffer, sizeof(sBuffer), "%s/%s", path, sPath);

		//Check if we're on the exclusion list and if we are, skip us.
		if (array_Exclusions.FindString(sBuffer) != -1)
		{
			continue;
		}

		switch (fType)
		{
			case FileType_Directory:
			{
				//This is a directory so we should recursively auto load its files the same way.
				AutoLoadFiles(sBuffer, load, print);
			}

			case FileType_File:
			{
				//Remove any dots and slashes at the start of the path.
				RemoveFrontString(sBuffer, sizeof(sBuffer), 2);
				
				#if defined DEBUG
				LogToFileEx("addons/sourcemod/logs/autofileloader.debug.log", "Adding To Downloads Table: %s", sBuffer);
				#endif

				//Add this file to the downloads table if it has a valid extension.
				for (int i = 0; i < array_Downloadables.Length; i++)
				{
					char sExtension[6];
					array_Downloadables.GetString(i, sExtension, sizeof(sExtension));

					if (StrContains(sBuffer, sExtension) != -1)
					{
						if (print)
						{
							LogToFileEx2("addons/sourcemod/logs/autofileloader.list.log", "Download: %s", sBuffer);
						}
						
						AddFileToDownloadsTable(sBuffer);
						break;
					}
				}
				
				switch (load)
				{
					case Load_Materials:
					{
						if (StrContains(sPath, "decals") != -1)
						{
							#if defined DEBUG
							LogToFileEx("addons/sourcemod/logs/autofileloader.debug.log", "Precaching Decal: %s", sBuffer);
							#endif
							
							if (print)
							{
								LogToFileEx2("addons/sourcemod/logs/autofileloader.list.log", "Precache Material: %s", sBuffer);
							}
							
							PrecacheDecal(sBuffer);
						}
					}

					case Load_Models:
					{
						//We only need to precache the MDL file itself.
						if (StrContains(sPath, ".mdl") != -1)
						{
							#if defined DEBUG
							LogToFileEx("addons/sourcemod/logs/autofileloader.debug.log", "Precaching Model: %s", sBuffer);
							#endif
							
							if (print)
							{
								LogToFileEx2("addons/sourcemod/logs/autofileloader.list.log", "Precache Model: %s", sBuffer);
							}

							//Model paths require the "models/" prefix to be removed when precaching, Valves rules.
							ReplaceString(sBuffer, sizeof(sBuffer), "models/", "");
							PrecacheModel(sBuffer);
						}
					}

					case Load_Sounds:
					{
						if (StrContains(sPath, ".wav") != -1 || StrContains(sPath, ".mp3") != -1)
						{
							#if defined DEBUG
							LogToFileEx("addons/sourcemod/logs/autofileloader.debug.log", "Precaching Sound: %s", sBuffer);
							#endif
							
							if (print)
							{
								LogToFileEx2("addons/sourcemod/logs/autofileloader.list.log", "Precache Sound: %s", sBuffer);
							}
							
							//Sound paths require the "sound/" prefix to be removed when precaching, Valves rules.
							ReplaceString(sBuffer, sizeof(sBuffer), "sound/", "");
							PrecacheSound(sBuffer);
						}
					}
					
					case Load_Particles:
					{
						if (StrContains(sPath, ".pcf") != -1)
						{
							#if defined DEBUG
							LogToFileEx("addons/sourcemod/logs/autofileloader.debug.log", "Precaching Particles File: %s", sBuffer);
							#endif
							
							if (print)
							{
								LogToFileEx2("addons/sourcemod/logs/autofileloader.list.log", "Precache Particles: %s", sBuffer);
							}
							
							PrecacheGeneric(sBuffer);
						}
					}
				}
			}
		}
	}

	delete dir;
	return true;
}

void LogToFileEx2(const char[] path, const char[] format, any ...)
{
	char sBuffer[1024];
	VFormat(sBuffer, sizeof(sBuffer), format, 3);
	
	File file = OpenFile(path, "a");
	
	if (file != null)
	{
		file.WriteLine(sBuffer);
	}
	
	delete file;
}

void RemoveFrontString(char[] strInput, int iSize, int iVar)
{
	strcopy(strInput, iSize, strInput[iVar]);
}