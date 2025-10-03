// *************************************************************************
//  This file is part of SBPP Base Votes.
//
//  Copyright (C) 2024 ampere <https://github.com/maxijabase>
//
//  SBPP Base Votes is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, per version 3 of the License.
//
//  SBPP Base Votes is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with SBPP Base Votes. If not, see <http://www.gnu.org/licenses/>.
//
// *************************************************************************

#define SBPP_BASEVOTES_VERSION "1.0.0"

/**
 * @section Vote type definitions
 */
enum SBPP_VoteType
{
	SBPP_VoteType_Map = 0,      /**< Map vote */
	SBPP_VoteType_Kick = 1,     /**< Kick vote */
	SBPP_VoteType_Ban = 2,      /**< Ban vote */
	SBPP_VoteType_Mute = 3,     /**< Mute vote */
	SBPP_VoteType_Gag = 4,      /**< Gag vote */
	SBPP_VoteType_Question = 5  /**< Generic question vote */
};

/**
 * @section Vote choice definitions
 */
enum SBPP_VoteChoice
{
	SBPP_VoteChoice_Yes = 1,    /**< Vote yes */
	SBPP_VoteChoice_No = 0      /**< Vote no */
};

/**
 * @section Vote result definitions
 */
enum SBPP_VoteResult
{
	SBPP_VoteResult_Success = 1,    /**< Vote passed */
	SBPP_VoteResult_Failed = 0,     /**< Vote failed */
	SBPP_VoteResult_Cancelled = -1  /**< Vote was cancelled (no votes) */
};

/*********************************************************
 * Called when a vote is initiated by a player.
 *
 * @param iInitiator    The client index of the player who initiated the vote
 * @param voteType      The type of vote being initiated (see SBPP_VoteType enum)
 * @param iTarget       The client index of the target player (-1 if not applicable)
 * @param sTargetName   The name of the target player (empty if not applicable)
 * @param sReason       The reason provided for the vote (empty if not provided)
 * @return              Plugin_Continue to allow the vote, Plugin_Handled or higher to block
 *********************************************************/
forward Action SBPP_OnVoteInitiated(int iInitiator, SBPP_VoteType voteType, int iTarget, const char[] sTargetName, const char[] sReason);

/*********************************************************
 * Called after a vote has been successfully initiated.
 *
 * @param iInitiator    The client index of the player who initiated the vote
 * @param voteType      The type of vote being initiated (see SBPP_VoteType enum)
 * @param iTarget       The client index of the target player (-1 if not applicable)
 * @param sTargetName   The name of the target player (empty if not applicable)
 * @param sReason       The reason provided for the vote (empty if not provided)
 * @noreturn
 *********************************************************/
forward void SBPP_OnVoteInitiated_Post(int iInitiator, SBPP_VoteType voteType, int iTarget, const char[] sTargetName, const char[] sReason);

/*********************************************************
 * Called when a player casts their vote.
 *
 * @param iVoter        The client index of the player voting
 * @param voteType      The type of vote (see SBPP_VoteType enum)
 * @param choice        The choice the player made (see SBPP_VoteChoice enum)
 * @param sTargetName   The name of the target player (empty if not applicable)
 * @noreturn
 *********************************************************/
forward void SBPP_OnPlayerVoted(int iVoter, SBPP_VoteType voteType, SBPP_VoteChoice choice, const char[] sTargetName);

/*********************************************************
 * Called when a vote ends.
 *
 * @param voteType      The type of vote that ended (see SBPP_VoteType enum)
 * @param result        The result of the vote (see SBPP_VoteResult enum)
 * @param iTarget       The client index of the target player (-1 if not applicable or disconnected)
 * @param sTargetName   The name of the target player (empty if not applicable)
 * @param sTargetAuth   The SteamID of the target player (empty if not applicable)
 * @param sReason       The reason provided for the vote (empty if not provided)
 * @param iVotesYes     Number of yes votes
 * @param iVotesNo      Number of no votes
 * @param iVotesTotal   Total number of votes cast
 * @param fPercentage   Percentage of yes votes (0.0 - 1.0)
 * @noreturn
 *********************************************************/
forward void SBPP_OnVoteEnded(SBPP_VoteType voteType, SBPP_VoteResult result, int iTarget, const char[] sTargetName, 
							  const char[] sTargetAuth, const char[] sReason, int iVotesYes, int iVotesNo, 
							  int iVotesTotal, float fPercentage);

/*********************************************************
 * Called right before a successful vote action is executed.
 * This is called after the vote passed and before the punishment is applied.
 *
 * @param voteType      The type of vote (see SBPP_VoteType enum)
 * @param iTarget       The client index of the target player (-1 if disconnected)
 * @param sTargetName   The name of the target player
 * @param sTargetAuth   The SteamID of the target player (may be empty)
 * @param sReason       The reason for the vote
 * @param iDuration     Duration in minutes (for bans/mutes/gags, -1 for kicks/maps)
 * @return              Plugin_Continue to allow execution, Plugin_Handled or higher to block
 *********************************************************/
forward Action SBPP_OnVoteActionExecute(SBPP_VoteType voteType, int iTarget, const char[] sTargetName, 
										const char[] sTargetAuth, const char[] sReason, int iDuration);

/*********************************************************
 * Called after a successful vote action has been executed.
 *
 * @param voteType      The type of vote (see SBPP_VoteType enum)
 * @param iTarget       The client index of the target player (-1 if disconnected)
 * @param sTargetName   The name of the target player
 * @param sTargetAuth   The SteamID of the target player (may be empty)
 * @param sReason       The reason for the vote
 * @param iDuration     Duration in minutes (for bans/mutes/gags, -1 for kicks/maps)
 * @noreturn
 *********************************************************/
forward void SBPP_OnVoteActionExecute_Post(SBPP_VoteType voteType, int iTarget, const char[] sTargetName, 
										   const char[] sTargetAuth, const char[] sReason, int iDuration);
