#include <stdio.h>
#include "utlist.h"
#include "utils.h"

#include "memory_controller.h"
#include "params.h"

/* A scheduling algorithm based on Priority Based Fair Scheduling policy
 *
 * A basic FCFS policy augmented with a clever close-page policy.
   Instead of immediately closing the page, wait for a few idle cycles to close
   the page based on the hit rate of the thread on each core which has last accessed this
   row. 
   
   This is as follows: hit rate = hits_in_row_buffer / accesses 

   break even hit rate to keep page open is T_RP / (T_RP+T_RCD)

   If the memory controller is unable to issue a command this cycle, find
   a bank that recently serviced a column-wr and close it (precharge it). */


extern long long int CYCLE_VAL;
#define MAX_THREADS  64

long CAPN;

/* A data structure to see if a bank is a candidate for precharge. */
int recent_colacc[MAX_NUM_CHANNELS][MAX_NUM_RANKS][MAX_NUM_BANKS];

/* Keeping track of how many preemptive precharges are performed. */
long long int num_aggr_precharge = 0;
double priority[MAX_NUM_CHANNELS][MAX_THREADS];
long long accesses[MAX_NUM_CHANNELS][MAX_THREADS];
long long hits[MAX_NUM_CHANNELS][MAX_THREADS];

int get_core_highest_priority(int channel)
{
  int max_index = 0;
  for (int i = 0; i < MAX_THREADS; i++)
    if (priority[channel][max_index] > priority[channel][i])
        max_index = i;

  return max_index;
}


  void
init_scheduler_vars ()
{
  CAPN = T_RP / (T_RP+T_RCD);
  // initialize all scheduler variables here
  int i, j, k;
  for (i = 0; i < MAX_NUM_CHANNELS; i++)
  {
    for (j = 0; j < MAX_NUM_RANKS; j++)
    {
      for (k = 0; k < MAX_NUM_BANKS; k++)
      {
        recent_colacc[i][j][k] = 0;
      }
    }
  }
  for(int channel = 0; channel < NUM_CHANNELS; channel++) 
    for(int core =0; core < NUMCORES; core++)  {
      accesses[channel][core] = 0;
      hits[channel][core]     = 0;
    }



  return;
}

// write queue high water mark; begin draining writes if write queue exceeds this value
#define HI_WM 40

// end write queue drain once write queue has this many writes in it
#define LO_WM 20

// 1 means we are in write-drain mode for that channel
int drain_writes[MAX_NUM_CHANNELS];

/* Each cycle it is possible to issue a valid command from the read or write queues
   OR
   a valid precharge command to any bank (issue_precharge_command())
   OR
   a valid precharge_all bank command to a rank (issue_all_bank_precharge_command())
   OR
   a power_down command (issue_powerdown_command()), programmed either for fast or slow exit mode
   OR
   a refresh command (issue_refresh_command())
   OR
   a power_up command (issue_powerup_command())
   OR
   an activate to a specific row (issue_activate_command()).

   If a COL-RD or COL-WR is picked for issue, the scheduler also has the
   option to issue an auto-precharge in this cycle (issue_autoprecharge()).

   Before issuing a command it is important to check if it is issuable. For the RD/WR queue resident commands, checking the "command_issuable" flag is necessary. To check if the other commands (mentioned above) can be issued, it is important to check one of the following functions: is_precharge_allowed, is_all_bank_precharge_allowed, is_powerdown_fast_allowed, is_powerdown_slow_allowed, is_powerup_allowed, is_refresh_allowed, is_autoprecharge_allowed, is_activate_allowed.
   */


  void
schedule (int channel)
{
  request_t *rd_ptr = NULL;
  request_t *wr_ptr = NULL;
  int i, j;


  // if in write drain mode, keep draining writes until the
  // write queue occupancy drops to LO_WM
  if (drain_writes[channel] && (write_queue_length[channel] > LO_WM))
  {
    drain_writes[channel] = 1;	// Keep draining.
  }
  else
  {
    drain_writes[channel] = 0;	// No need to drain.
  }

  // initiate write drain if either the write queue occupancy
  // has reached the HI_WM , OR, if there are no pending read
  // requests
  if (write_queue_length[channel] > HI_WM)
  {
    drain_writes[channel] = 1;
  }
  else
  {
    if (!read_queue_length[channel])
      drain_writes[channel] = 1;
  }


  // If in write drain mode, look through all the write queue
  // elements (already arranged in the order of arrival), and
  // issue the command for the first request that is ready
  if (drain_writes[channel])
  {

    LL_FOREACH (write_queue_head[channel], wr_ptr)
    {
      if (wr_ptr->command_issuable)
      {
        /* Before issuing the command, see if this bank is now a candidate for closure (if it just did a column-rd/wr).
           If the bank just did an activate or precharge, it is not a candidate for closure. */
        if (wr_ptr->next_command == COL_WRITE_CMD)
        {
          if (wr_ptr->thread_id != get_core_highest_priority(channel))
            recent_colacc[channel][wr_ptr->dram_addr.rank][wr_ptr->dram_addr.bank] = 1;
          else
            recent_colacc[channel][wr_ptr->dram_addr.rank][wr_ptr->dram_addr.bank] = 0;
          hits[channel][wr_ptr->thread_id]++;
        }
        if (wr_ptr->next_command == ACT_CMD)
        {
          recent_colacc[channel][wr_ptr->dram_addr.rank][wr_ptr->dram_addr.bank] = 0;
        }
        if (wr_ptr->next_command == PRE_CMD)
        {
          recent_colacc[channel][wr_ptr->dram_addr.rank][wr_ptr->dram_addr.bank] = 0;
        }
        issue_request_command (wr_ptr);
        accesses[channel][wr_ptr->thread_id]++;
        break;
      }
    }
  }

  // Draining Reads
  // look through the queue and find the first request whose
  // command can be issued in this cycle and issue it 
  // Simple FCFS 
  if (!drain_writes[channel])
  {
    LL_FOREACH (read_queue_head[channel], rd_ptr)
    {
      if (rd_ptr->command_issuable)
      {
        /* Before issuing the command, see if this bank is now a candidate for closure (if it just did a column-rd/wr).
           If the bank just did an activate or precharge, it is not a candidate for closure. */
        if (rd_ptr->next_command == COL_READ_CMD)
        {
          if (rd_ptr->thread_id != get_core_highest_priority(channel))
            recent_colacc[channel][rd_ptr->dram_addr.rank][rd_ptr->dram_addr.bank] = 1;
          else
            recent_colacc[channel][rd_ptr->dram_addr.rank][rd_ptr->dram_addr.bank] = 0;
          hits[channel][rd_ptr->thread_id]++;
        }
        if (rd_ptr->next_command == ACT_CMD)
        {
          recent_colacc[channel][rd_ptr->dram_addr.rank][rd_ptr->dram_addr.bank] = 0;
        }
        if (rd_ptr->next_command == PRE_CMD)
        {
          recent_colacc[channel][rd_ptr->dram_addr.rank][rd_ptr->dram_addr.bank] = 0;
        }
        issue_request_command (rd_ptr);
        accesses[channel][rd_ptr->thread_id]++;
        break;
      }
    }
  }

  /* If a command hasn't yet been issued to this channel in this cycle, issue a precharge. */
  if (!command_issued_current_cycle[channel])
  {
    for (i = 0; i < NUM_RANKS; i++)
    {
      for (j = 0; j < NUM_BANKS; j++)
      {			/* For all banks on the channel.. */
        if (recent_colacc[channel][i][j])
        {		/* See if this bank is a candidate. */
          if (is_precharge_allowed (channel, i, j))
          {		/* See if precharge is doable. */
            if (issue_precharge_command (channel, i, j))
            {
              num_aggr_precharge++;
              recent_colacc[channel][i][j] = 0;
            }
          }
        }
      }
    }
  }

  long long total_accesses = 0;
  long long total_hits     = 0;
  // update priorities
  for (int core = 0; core < MAX_THREADS; core++) 
  {
    total_accesses += accesses[channel][core];
    total_hits     += hits[channel][core];
  }

  for (int core = 0; core < MAX_THREADS; core++) 
  {
    if (total_hits && total_accesses)
      priority[channel][core] = hits[channel][core] / total_hits +  accesses[channel][core] / total_accesses;
  }

}

  void
scheduler_stats ()
{
  /* Nothing to print for now. */
  printf ("Number of aggressive precharges: %lld\n", num_aggr_precharge);
}
