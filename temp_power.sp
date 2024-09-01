#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <admin>
#include <clients>
#include <morecolors>
#include <colors>

#pragma newdecls required

#define DATE_SIZE 14
#define STEAM_ID_SIZE 100
#define RIGHTS_SIZE 100

#define PLUGIN_VERSION "0.0.3"

enum struct Date
{
	int year;
	int month;
	int day;

	void ParseString(const char[] strDate)
	{
		char parts[3][5];
		ExplodeString(strDate, ".", parts, 3, sizeof(parts[]));

		this.year = StringToInt(parts[0]);
		this.month = StringToInt(parts[1]);
		this.day = StringToInt(parts[2]);
	}

	void SetToCurrentDate()
	{
		char strDate[DATE_SIZE];
		FormatTime(strDate, sizeof(strDate), "%Y.%m.%d", GetTime());

		this.ParseString(strDate);
	}

	bool IsDatePassed()
	{
		Date current;
		current.SetToCurrentDate();

		if (this.year != current.year)
			return (this.year < current.year);

		if (this.month != current.month)
			return (this.month < current.month);

		return (this.day < current.day);
	}

	void ToString(char[] strDate)
	{
		Format(strDate, DATE_SIZE, "%d.%d.%d", this.year, this.month, this.day);
	}
}

enum struct PowerUser
{
	char steamID[STEAM_ID_SIZE];
	char flags[RIGHTS_SIZE];
	int immunityLevel;
	Date expDate;
}

StringMap g_poweredUsers;

public Plugin myinfo =
{
	name = "Temp Power - VIP manager",
	author = "Oplkill",
	description = "Managing temp admins/VIPS",
	version = PLUGIN_VERSION,
	url = "https://github.com/Oplkill/Temp-Power-Sourcemod-VIP-manager"
}

public void OnPluginStart()
{
	g_poweredUsers = new StringMap();
	LoadTranslations("temp_power.phrases");

	CreateConVar("sm_tep_version", PLUGIN_VERSION, "Temp Power VIP manager version", FCVAR_DONTRECORD | FCVAR_NOTIFY);

	ReadUsersConfig(true);

	HookEvent("teamplay_round_start", OnRoundStart);
}

public void OnRoundStart(Handle hEvent, const char[] strEventName, bool bDontBroadcast)
{
	ReadUsersConfig(false);
}

public void OnClientPostAdminCheck(int client)
{
	char steamID[STEAM_ID_SIZE];
	GetClientAuthId(client, AuthId_Steam2, steamID, sizeof(steamID));

	if (!g_poweredUsers.ContainsKey(steamID))
	{
		PrintToServer("[Temp Power] No user with that steam id '%s'", steamID);
		return;
	}

	PrintToServer("[Temp Power] User with '%s'", steamID);

	PowerUser power;
	g_poweredUsers.GetArray(steamID, power, sizeof(PowerUser));

	char expDate[DATE_SIZE];
	power.expDate.ToString(expDate);

	if (power.expDate.IsDatePassed())
	{
		CPrintToChat(client, "%T", "Your_vip_is_ended", LANG_SERVER);
	}
	else
	{
		SetClentTempVip(client, power.flags, power.immunityLevel);
		CPrintToChat(client, "%T", "Your_vip_ends", LANG_SERVER, expDate);
	}
}

stock bool IsValidClient(int client)
{
	if (client < 1 || client > MaxClients)
		return false;

	if (!IsClientInGame(client))
		return false;

	return true;
}

void ReadUsersConfig(bool removeExpired)
{
	g_poweredUsers.Clear();

	char strPath[256];
	BuildPath(Path_SM, strPath, sizeof(strPath), "configs/temp_users.cfg");

	if (!FileExists(strPath))
	{
		SetFailState("[Temp Power] Failed to find temp_users.cfg in configs/ folder!");
		PrintToServer("[Temp Power] Failed to find temp_users.cfg in configs/ folder!");
		return;
	}

	KeyValues hKv = CreateKeyValues("Users");
	if (!(FileToKeyValues(hKv, strPath) && hKv.GotoFirstSubKey()))
	{
		if (hKv != INVALID_HANDLE) 
			hKv.Close();
		SetFailState("[Temp Power] Can't parse users confing.");
		PrintToServer("[Temp Power] Can't parse users confing.");
		return;
	}

	PrintToServer("[Temp Power] STARTING LOADING.");

	char strDate[DATE_SIZE];
	bool isFileChanged = false;

	while (true)
	{
		PowerUser user;

		hKv.GetSectionName(user.steamID, sizeof(user.steamID));

		hKv.GetString("flags", user.flags, sizeof(user.flags));
		hKv.GetString("exp_date", strDate, sizeof(strDate));
		user.immunityLevel = hKv.GetNum("immun_level", 0);

		user.expDate.ParseString(strDate);

		if (user.expDate.IsDatePassed())
		{
			if (removeExpired)
			{
				isFileChanged = true;
				PrintToServer("[Temp Power] removing old record for '%s'", user.steamID);
				int deleteResult = hKv.DeleteThis();

				PrintToServer("[Temp Power] deleteResult '%d'", deleteResult);
				
				if (deleteResult == 1)
					continue;
				else if (deleteResult == -1)
					break;
				else
				{
					PrintToServer("[Temp Power] FAILED to remove '%s'!!!", user.steamID);
				}
			}
		}
		else
		{
			g_poweredUsers.SetArray(user.steamID, user, sizeof(PowerUser));
			PrintToServer("[Temp Power] Found VIP '%s', that expires at %s", user.steamID, strDate);
		}

		if (!hKv.GotoNextKey())
			break;
	}

	if (isFileChanged)
	{
		hKv.Rewind();
		if (!hKv.ExportToFile(strPath))
		{
			PrintToServer("[Temp Power] FAILED to update config file");
		}
	}

	hKv.Close();

	PrintToServer("[Temp Power] All vips loaded");
}

/// Sets player temp vip that removing by disconnecting
void SetClentTempVip(int client, char[] flags, int immunityLevel)
{
	PrintToServer("[Temp Power] giving vip to client %d '%s' immlevel %d", client, flags, immunityLevel);

	GroupId grpID = FindAdmGroup(flags);
	AdminId admin = CreateAdmin();

	if(grpID == INVALID_GROUP_ID)
	{
		SetAdminImmunityLevel(admin, immunityLevel);
		for(int i = 0; i < strlen(flags); i++)
		{
			AdminFlag flag;
			if(FindFlagByChar(flags[i], flag))
				SetAdminFlag(admin, flag, true);
			else
				PrintToServer("[Temp Power] Error : flag '%c' unknow !", flags[i]);
		}
	}
	else
	{
		int bitFlags = GetAdmGroupAddFlags(grpID);
		AdminFlag admflags[40];
		//BitToFlag(bitFlags, flag);
		FlagBitsToArray(bitFlags, admflags, sizeof(admflags));
		for(int i = 0; i < sizeof(admflags); i++)
			SetAdminFlag(admin, admflags[i], true);
	}
	
	SetUserAdmin(client, admin, true);

	PrintToServer("[Temp Power] Successfully gived VIP to client %d", client);
}