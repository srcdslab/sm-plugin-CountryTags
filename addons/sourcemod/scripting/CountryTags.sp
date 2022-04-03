#include <clientprefs>
#include <cstrike>
#include <geoip>
#include <sdkhooks>
#include <sdktools>
#include <sourcemod>
#tryinclude <ScoreboardCustomLevels>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_NAME    "Country Clan Tags"
#define PLUGIN_VERSION "2.2"

#define SIZEOF_BOTTAG 4

ConVar g_cvTagMethod = null;
ConVar g_cvTagLen    = null;
ConVar g_cvBotTags   = null;
ConVar g_cvShowFlags = null;

ArrayList g_aryBotTags     = null;
KeyValues g_kvCountryFlags = null;

char g_sCountryTag[MAXPLAYERS + 1][6];
int  g_iTagMethod = 1;
int  g_iTagLen    = 2;

int m_iOffset                = -1;
int m_iLevel[MAXPLAYERS + 1] = { -1, ... };

bool g_bCustomLevels = false;

bool g_bLateLoad = false;

public Plugin myinfo =
{
	name        = PLUGIN_NAME,
	author      = "GoD-Tony, Franc1sco franug, maxime1907",
	description = "Assigns clan tags and flags based on the player's country",
	version     = PLUGIN_VERSION,
	url         = "http://www.sourcemod.net/"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	MarkNativeAsOptional("SCL_GetLevel");

	g_bLateLoad = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	CreateConVar("sm_countrytags_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DONTRECORD);

	g_cvTagMethod = CreateConVar("sm_countrytags", "1", "Determines plugin functionality. (0 = Disabled, 1 = Tag all players, 2 = Tag tagless players)", FCVAR_NONE, true, 0.0, true, 2.0);
	g_cvTagLen    = CreateConVar("sm_countrytags_length", "3", "Country code length. (2 = CA,US,etc. 3 = CAN,USA,etc.)", FCVAR_NONE, true, 2.0, true, 3.0);
	g_cvBotTags   = CreateConVar("sm_countrytags_bots", "CAN,USA", "Tags to assign bots. Separate tags by commas.", FCVAR_NONE);
	g_cvShowFlags = CreateConVar("sm_countrytags_showflags", "1", "Show country flags in scoreboard.", FCVAR_NONE, true, 0.0, true, 1.0);

	HookConVarChange(g_cvTagMethod, OnConVarChange);
	HookConVarChange(g_cvTagLen, OnConVarChange);
	HookConVarChange(g_cvBotTags, OnConVarChange);

	g_iTagMethod = GetConVarInt(g_cvTagMethod);
	g_iTagLen    = GetConVarInt(g_cvTagLen);

	g_aryBotTags = CreateArray(SIZEOF_BOTTAG);
	PushArrayString(g_aryBotTags, "CAN");
	PushArrayString(g_aryBotTags, "USA");

	m_iOffset = FindSendPropInfo("CCSPlayerResource", "m_nPersonaDataPublicLevel");

	g_bCustomLevels = LibraryExists("ScoreboardCustomLevels");

	AutoExecConfig(true);
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "ScoreboardCustomLevels"))
		g_bCustomLevels = true;
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "ScoreboardCustomLevels"))
		g_bCustomLevels = false;
}

public void OnConVarChange(Handle hCvar, const char[] oldValue, const char[] newValue)
{
	if (hCvar == g_cvTagMethod)
	{
		g_iTagMethod = StringToInt(newValue);
	}
	else if (hCvar == g_cvTagLen)
	{
		g_iTagLen = StringToInt(newValue);
	}
	else if (hCvar == g_cvBotTags)
	{
		ClearArray(g_aryBotTags);
		ExplodeString_adt(newValue, ",", g_aryBotTags, SIZEOF_BOTTAG);
	}
}

public void OnClientPostAdminCheck(int client)
{
	char ip[16];
	char code2[3];

	m_iLevel[client] = -1;

	if (IsFakeClient(client))
	{
		// Disabled tag for bots
		if (GetArraySize(g_aryBotTags) <= 0)
			return;

		int idx = GetRandomInt(0, GetArraySize(g_aryBotTags) - 1);
		GetArrayString(g_aryBotTags, idx, code2, SIZEOF_BOTTAG);
	}
	else
	{
		if (!GetClientIP(client, ip, sizeof(ip)) || !IsLocalAddress(ip) && !GeoipCode2(ip, code2))
			code2 = "???";

		if (IsLocalAddress(ip))
		{
			char sNetIP[32] = "";

			ConVar g_cvNetPublicAddr = FindConVar("net_public_adr");
			if (g_cvNetPublicAddr != null)
				g_cvNetPublicAddr.GetString(sNetIP, sizeof(sNetIP));

			if (!GeoipCode2(sNetIP, code2))
				code2 = "???";
		}
	}

	if (g_cvShowFlags.BoolValue)
	{
		if (KvJumpToKey(g_kvCountryFlags, code2))
			m_iLevel[client] = KvGetNum(g_kvCountryFlags, "index");

		KvRewind(g_kvCountryFlags);
	}

	Format(g_sCountryTag[client], sizeof(g_sCountryTag[]), "[%s]", code2);
}

public void OnClientDisconnect(int client)
{
	m_iLevel[client] = -1;
}

public void OnClientSettingsChanged(int client)
{
	/* Set a client's clan tag once they finished loading their own tag. */
	if (IsClientInGame(client) && TagPlayer(client))
	{
		CS_SetClientClanTag(client, g_sCountryTag[client]);
	}
}

public void OnConfigsExecuted()
{
	if (!g_cvShowFlags.BoolValue)
		return;

	char sBuffer[PLATFORM_MAX_PATH];
	char m_cFilePath[PLATFORM_MAX_PATH];

	BuildPath(Path_SM, m_cFilePath, sizeof(m_cFilePath), "configs/countryflags.cfg");

	SDKHook(GetPlayerResourceEntity(), SDKHook_ThinkPost, OnThinkPost);

	if (g_kvCountryFlags != null)
		g_kvCountryFlags.Close();

	g_kvCountryFlags = CreateKeyValues("CountryFlags");
	FileToKeyValues(g_kvCountryFlags, m_cFilePath);

	if (!KvGotoFirstSubKey(g_kvCountryFlags))
	{
		LogError("Could not parse country flags config: %s", m_cFilePath);
		return;
	}

	do
	{
		Format(sBuffer, sizeof(sBuffer), "materials/panorama/images/icons/xp/level%i.png", KvGetNum(g_kvCountryFlags, "index"));
		AddFileToDownloadsTable(sBuffer);
	}
	while (KvGotoNextKey(g_kvCountryFlags));

	KvRewind(g_kvCountryFlags);

	if (g_bLateLoad)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientConnected(i))
			{
				OnClientPostAdminCheck(i);
				OnClientSettingsChanged(i);
			}
		}
		g_bLateLoad = false;
	}
}

public void OnThinkPost(int m_iEntity)
{
	if (!g_cvShowFlags.BoolValue)
		return;

	int m_iLevelTemp[MAXPLAYERS + 1] = 0;
	GetEntDataArray(m_iEntity, m_iOffset, m_iLevelTemp, MAXPLAYERS + 1);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (m_iLevel[i] != -1)
		{
			if (m_iLevel[i] != m_iLevelTemp[i])
			{
#if defined _ScoreboardCustomLevels_included
				if (g_bCustomLevels && SCL_GetLevel(i) > 0)
					continue;    // dont overwritte other custom level
#endif

				SetEntData(m_iEntity, m_iOffset + (i * 4), m_iLevel[i]);
			}
		}
	}
}

stock bool TagPlayer(int client)
{
	/* Should we be tagging this player? */
	char sClanID[32];
	GetClientInfo(client, "cl_clanid", sClanID, sizeof(sClanID));

	if (g_iTagMethod == 1 || (g_iTagMethod == 2 && StringToInt(sClanID) == 0))
		return true;

	return false;
}

stock void ExplodeString_adt(const char[] text, const char[] split, Handle array, int size)
{
	/* Rewritten ExplodeString stock (string.inc) using an adt array. */
	char[] sBuffer = new char[size];
	int idx, reloc_idx;

	while ((idx = SplitString(text[reloc_idx], split, sBuffer, size)) != -1)
	{
		PushArrayString(array, sBuffer);

		reloc_idx += idx;

		if (text[reloc_idx] == '\0')
			break;
	}

	if (text[reloc_idx] != '\0')
	{
		strcopy(sBuffer, size, text[reloc_idx]);
		PushArrayString(array, sBuffer);
	}
}

stock bool IsLocalAddress(const char ip[16])
{
	// 192.168.0.0 - 192.168.255.255 (65,536 IP addresses)
	// 10.0.0.0 - 10.255.255.255 (16,777,216 IP addresses)
	if (StrContains(ip, "192.168", false) > -1 || StrContains(ip, "10.", false) > -1)
	{
		return true;
	}

	// 172.16.0.0 - 172.31.255.255 (1,048,576 IP addresses)
	char octets[4][3];
	if (ExplodeString(ip, ".", octets, 4, 3) == 4)
	{
		if (StrContains(octets[0], "172", false) > -1)
		{
			int octet = StringToInt(octets[1]);

			return (!(octet < 16) || !(octet > 31));
		}
	}

	return false;
}
