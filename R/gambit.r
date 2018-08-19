example.gambit.solve.eq = function() {
	# set working directory to project directory
  setwd("D:/libraries/gtree/myproject")
	gameId = "TestGambit"
	gameId = "UltimatumGame"
	tg = get.tg(gameId = gameId,never.load = !FALSE)

	eq.li = gambit.solve.eq(tg)

	eq.li = get.eq(tg)
	eq.li
  eqo.df = eq.outcomes(eq.li, tg=tg)
  eqo.df

  ceqo = cond.eq.outcomes(eq.li, cond=list(probA=c(0.2,0.8)),tg = tg, expected=TRUE)

  eceqo = expected.cond.eq.outcomes(ceqo)



	# Inequity aversion
  alpha = 0.371; beta=0.31
  util.funs = list(ineqAvUtil(1, alpha,beta),ineqAvUtil(2,alpha,beta))
  eq.li = get.eq(tg, util.funs = util.funs)
  #eq.li = get.eq(tg, util.funs = util.funs, just.spe=FALSE)
  eqo.df = eq.outcomes(eq.li, tg=tg)
  eqo.df

  eeqo.df = expected.eq.outcomes(eqo.df)


  # conditional equilibrium outcomes for all maxOffers
  cond = expand.grid(maxOffer = unique(tg$oco.df$maxOffer))
  eo = eq.li %>%
  	cond.eq.outcomes(cond = cond, tg=tg) %>%
  	expected.eq.outcomes(group.vars = c("eq.ind",names(cond)))

  library(ggplot2)
  ggplot(eo, aes(x=maxOffer, y=accept, fill=is.eqo)) + geom_bar(stat = "identity") + ggtitle("Acceptance probabilty as function of maxOffer")

  ggplot(eo, aes(x=maxOffer, y=payoff_1, fill=is.eqo)) + geom_bar(stat = "identity")

  ggplot(eo, aes(x=maxOffer, y=util_1, fill=is.eqo)) + geom_bar(stat = "identity")


  # solve mixed equilibria
 	gameId = "Pennies"
	tg = get.tg(gameId = gameId,never.load = FALSE)
	eq.li = gambit.solve.eq(tg, mixed=TRUE)

	eq.li = gambit.solve.eq(tg, mixed=TRUE, solver="gambit-enummixed -q -d 4")


	eqo = eq.outcomes(eq.li, tg=tg)
  eeqo = expected.eq.outcomes(eqo)

}


#' compute expected equilibrium outcomes
#' taking expectations over moves of nature
expected.eq.outcomes = function(eqo.df=NULL, group.vars=c("eq.ind", "eqo.ind"),eq.li=NULL, tg=NULL) {
	restore.point("expected.eq.outcomes")


  if (!is.null(eq.li) & is.null(eqo.df)) {
    eqo.df = eq.outcomes(eq.li,tg = tg)
  }

	if (NROW(eqo.df)==0) return(eqo.df)

	vars = setdiff(colnames(eqo.df),group.vars)
	group.vars = intersect(group.vars, colnames(eqo.df))

	if ("eq.ind" %in% group.vars) {
		if (is.list(eqo.df[["eq.ind"]])) {
			group.vars = setdiff(group.vars, "eq.ind")
			eqo.df = select(eqo.df, - eq.ind)
		}
	}

	#vars = vars[sapply(vars, function(var) is.numeric(eqo.df[[var]]))]

	fun = function(df) {
		restore.point("fun")
		vals = lapply(vars, function(var) {
			if (is.character(df[[var]]) & var != "variant") {
				restore.point("jhsjkhfkdhfh")
				sdf = group_by_(df, "eqo.ind", var) %>%
					s_summarise(paste0('
						.sum.prob = sum(.prob),
						.var.prob = paste0(first(',var,'),ifelse(.sum.prob < 1,paste0("(",round(.sum.prob,2),")"),""))'
					))
				return(paste0(unique(sdf[[".var.prob"]]), collapse=","))
			}

			if (var == ".outcome" | is.character(df[[var]]))
				return(paste0(unique(df[[var]]), collapse=","))
			if (var == ".prob")
				return(sum(df[[var]]))

			if (var=="is.eqo") {
				return(df[[var]][1])
			}

			if (is.numeric(df[[var]]) | is.logical(df[[var]]))
				return(sum(df[[var]] * df$.prob) / sum(df$.prob))

			return(NULL)
		})
		names(vals) = vars
		vals = vals[sapply(vals, function(val) !is.null(val))]
		as_data_frame(c(as.list(df[1,group.vars, drop=FALSE]),vals))
	}


	all.vars = c(group.vars, vars)
	res = eqo.df[,all.vars, drop=FALSE] %>%
		group_by_(.dots=group.vars) %>%
		do(fun(.)) %>%
	  ungroup()
	res

}


#' Finds one or all mixed strategy equilibria
gambit.solve.eq = function(tg, mixed=FALSE, just.spe=TRUE, efg.file=tg.efg.file.name(tg), efg.dir=get.efg.dir(tg$gameId), gambit.dir="", solver=NULL, eq.dir = get.eq.dir(tg$gameId), save.eq = TRUE, solvemode=NULL) {

  restore.point("gambit.solve.eq")


	# internal solver not using gambit
	if (isTRUE(solvemode=="spe_xs")) {
		return(solve.all.tg.spe(tg=tg, eq.dir=eq.dir,save.eq=save.eq))

	}

	solver = get.gambit.solver(solver=solver, mixed=mixed, just.spe=just.spe, solvemode=solvemode)

	#solver = "gambit-enumpure -q -P -D"
  start.time = Sys.time()

	com = paste0(gambit.dir, solver," ",file.path(efg.dir,efg.file))
  res  = system(com, intern=TRUE)
  status = attr(res,"status")
  if (isTRUE(status==1)) {
    stop(res)
  }

  # no equilibrium found
  if (length(res)==0)
    return(NULL)

  eq.li = gambit.out.txt.to.eq.li(res, tg=tg)

  solve.time = Sys.time()-start.time
  attr(eq.li,"solve.time") = solve.time

  if (save.eq) {
	 eq.id = get.eq.id(tg=tg, just.spe = just.spe, mixed=mixed, solvemode=solvemode)
	 save.eq.li(eq.li=eq.li, eq.id=eq.id,eq.dir=eq.dir,tg=tg)
  }

  eq.li
}

gambit.out.txt.to.eq.li = function(txt, tg, compact=FALSE) {
  restore.point("gambit.out.txt.to.eq.li")

  # no equilibrium found
  if (length(txt)==0) return(NULL)

  # in large games, equilibria may be longer than one line
  txt = merge.lines(txt)

  txt = sep.lines(txt,"NE,")[-1]



  # compact equilibirum representation
  # One equilibrium is just a vector that first contains for each
  # information set move the probability that it ocurs
  # afterwards, we also have the probability of moves of nature
  # ordered like .info.set.move.ind
  ceq.li = lapply(strsplit(txt,",",fixed=TRUE), function(vec) as.numeric(vec))


  # We have to inject these probabilties in our equilibrium template
  # tg$et.mat to generate an equilibrium data.frame eq.df
  # eq.mat will have the same dimensions than oco.df
  # each cell describes the probability that the particluar move
  # takes place:
  # (eq. prob for actions, prob for move of nature, 1 for transformations)
  # rowSums(eq.mat) then give the probability distribution over outcomes
  # for a given equilibrium.

  # et.ind are the indices of et.mat
  # that denote information sets
  et.ind = which(tg$et.mat<0)
  i = 1
  eq.li = lapply(seq_along(ceq.li), function(i) {
  	ceq.to.eq.mat(ceq = ceq.li[[i]],eq.ind=i, et.ind=et.ind, tg=tg)
  })


}

save.eq.li = function(eq.li, eq.id = get.eq.id(tg=tg,...),tg,  eq.dir=get.eq.dir(tg$gameId),...) {
	eq = list(
		eq.id = eq.id,
		tg.id = tg$tg.id,
		gameId = tg$gameId,
		variant = tg$variant,
		jg.hash = tg$jg.hash,
		eq.li = eq.li
	)
	file = paste0(eq.dir,"/",eq.id,".eq")
	saveRDS(eq,file)
}

# ceq is the returned vector by gambit describing an equilibrium
# it is a vector with as many elements as
# information set moves and contains values between 0 and 1, describing the move probabilty for each information set. A pure strategy contains only 0s and 1s.
# We convert it to eq.mat by writing the returned info set move probabilities at the right postion of et.mat.
#
# efg.move.inds is used because Gambit orders the information
# sets in the computed equilibria by player first and then
# in order of appearance in the efg file, while
# gtree orders them by stage.
ceq.to.eq.mat = function(ceq,eq.ind=1, tg,et.ind=which(tg$et.mat<0), efg.move.inds = compute.efg.move.inds(tg)) {
  restore.point("ceq.to.eq.mat")
  eq.mat = tg$et.mat

  # Account for different ordering
  # of gambit output and gtree's
  # information set numbers
  if (!is.null(efg.move.inds)) {
    ceq.gtree.order = integer(length(ceq))
    ceq.gtree.order[efg.move.inds] = ceq
    ceq = ceq.gtree.order
  }
  eq.mat[et.ind] = ceq[-eq.mat[et.ind]]

  .prob = rowProds(eq.mat)
  eq.mat = cbind(eq.mat, .prob)
  attr(eq.mat,"eq.ind") = eq.ind
  attr(eq.mat,"info.set.probs") = ceq
  eq.mat

}

get.eq.id = function(tg.id=tg$tg.id, just.spe=TRUE, mixed=FALSE, tg=NULL, solvemode=NULL) {
 	eq.id = paste0(tg$tg.id)
 	if (!is.null(solvemode)) {
 		return(paste0(eq.id,"__",solvemode))
 	}
 	if (just.spe)
 		eq.id = paste0(eq.id,"_spe")
 	if (mixed)
 		eq.id = paste0(eq.id,"_mixed")
 	eq.id

}

# equilibrium outcome data frame
eq.outcomes = function(eq.li, oco.df = tg$oco.df, tg=NULL, cond=NULL, compress=TRUE, as.data.frame=TRUE) {
  restore.point("eq.outcomes")
  eqo.li = lapply(eq.li, eq.outcome, oco.df=oco.df, tg=tg, cond=cond)
  if (length(eqo.li)>0) {
    is.null = sapply(eqo.li,is.null)
    eqo.li = eqo.li[!is.null]
  }
  if (compress) {
    # unique equilibrium ouctomes
    u.li = unique(eqo.li)
    org.ind = match(eqo.li, u.li)
    eqo.li = lapply(seq_along(u.li), function(i) {
    	restore.point("nsfndfn")
      eqo = u.li[[i]]
      eqo$eq.ind = replicate(NROW(eqo),which(org.ind==i), simplify=FALSE)
      eqo$eqo.ind = i
      eqo
    })
  }
  if (as.data.frame) {
    return(xs.col.order(bind_rows(eqo.li),tg))
  }
  return(eqo.li)
}

# return the equilibrium outcome
eq.outcome = function(eq.mat, oco.df=tg$oco.df, tg=NULL, cond=NULL) {
  restore.point("eq.outcome")
  if (!is.null(cond)) return(cond.eq.outcome(eq.mat, cond, oco.df, tg))
  oco.rows = eq.mat[,".prob"] > 0
  eo.df = oco.df[oco.rows,]
  if (NROW(eo.df)==0) return(NULL)

  eo.df$.prob = eq.mat[oco.rows,".prob"]
  xs.col.order(eo.df,tg)
}

#' Return a conditional equilibrium outcome
#'
#' @param eq.li The computed equilibria in gtree form
#' @param cond is a list with variable names and their assumed value
#' we only pick rows from oco.df in which the condition is satisfied
#' we set the probabilities of the conditioned variable values to 1
#' @param expected return expected conditional equilibrium outcomes
#' @param remove.duplicate.eq remove conditional outcomes that are duplicates but arise in different equilibria (who differ off the conditional path)
cond.eq.outcomes = function(eq.li, cond, tg=NULL,oco.df=tg$oco.df, expected=FALSE, remove.duplicate.eq=TRUE) {
  restore.point("cond.eq.outcomes")
	li = lapply(seq_along(eq.li), function(i) {
		eq.mat = eq.li[[i]]
		eq.ind = first.non.null(attr(eq.mat,"eq.ind"),i)
		cond.eq.outcome(eq.mat, cond=cond, oco.df=oco.df, tg=tg, eq.ind=eq.ind)
	})
	ceqo = xs.col.order(bind_rows(li),tg)

	# Remove duplicated equilibria that
	# have the same equilibrium outcomes
	if (remove.duplicate.eq) {
    cols = setdiff(colnames(ceqo),c("eq.ind","is.eqo"))
    ceqo = arrange(ceqo, ceqo.ind, !is.eqo)
    dupl = duplicated(ceqo[,cols])
    if (any(dupl))
      ceqo = ceqo[!dupl,,drop=FALSE]
	}

	if (expected)
    return(expected.cond.eq.outcomes(ceqo))


	return(ceqo)
}


expected.cond.eq.outcomes = function(ceqo.df) {
  restore.point("expected.cond.eq.outcomes")
  if (!"eqo.ind" %in% colnames(ceqo.df))
    ceqo.df$eqo.ind = ceqo.df$eq.ind
  res = expected.eq.outcomes(ceqo.df, group.vars=c("ceqo.ind","eq.ind"))
  res = select(res,-eqo.ind)
  res
}


#' return a conditional equilibrium outcome
#' cond is a list with variable names and their assumed value
#' we only pick rows from oco.df in which the condition is satisfied
#' we set the probabilities of the conditioned variable values to 1
cond.eq.outcome = function(eq.mat, cond, tg=NULL, oco.df=tg$oco.df, eq.ind = first.non.null(attr(eq.mat,"eq.ind"),NA), eo.df = eq.outcome(eq.mat=eq.mat, oco.df=oco.df, tg=tg), ceqo.ind=1) {
  restore.point("cond.eq.outcome")
	cond.df = as_data_frame(cond)

	# multiple rows, call function repeatedly
	if (NROW(cond.df)>1) {
		li = lapply(seq_len(NROW(cond.df)), function(row) {
			cond.eq.outcome(eq.mat=eq.mat, cond = cond.df[row,,drop=FALSE], oco.df = oco.df, tg =tg, eq.ind=eq.ind, eo.df = eo.df, ceqo.ind=row+ceqo.ind-1)
		})
		return(bind_rows(li))
	}
  restore.point("cond.eq.outcome.inner")

  cond.vars = names(cond)

  # only consider outcome rows where cond is satisfied
  rows = rep(TRUE,NROW(oco.df))
  for (var in cond.vars) {
    if (length(cond[[var]])==0) next
    rows = rows & (oco.df[[var]] %in% cond[[var]])
  }
  oco.df = oco.df[rows,,drop=FALSE]
  eq.mat = eq.mat[rows,,drop=FALSE]
  # set the probabilities of the variables, we condition on to 1
  eq.mat[,intersect(cond.vars,colnames(eq.mat))]=1
  # compute conditional outcome probabilities
  eq.mat[,".prob"] = rowProds(eq.mat[,-NCOL(eq.mat),drop=FALSE])

  oco.rows = eq.mat[,".prob"] > 0
  ceo.df = oco.df[oco.rows,]
  ceo.df$.prob = eq.mat[oco.rows,".prob"]
	ceo.df$eq.ind = eq.ind

	# find the conditional outcomes that are equilibrium outcomes
	keys = setdiff(
		intersect(colnames(ceo.df), colnames(eo.df)),
		c(".prob",".outcome","eq.ind","eqo.ind")
	)
	eo.df$is.eqo = TRUE
	ceo.df = left_join(ceo.df, eo.df[,c(keys,"is.eqo")],by=keys)
	ceo.df$ceqo.ind = ceqo.ind
	ceo.df$is.eqo[is.na(ceo.df$is.eqo)] = FALSE

  xs.col.order(ceo.df,tg)
}

xs.col.order = function(df, vg, mode="vars") {
	if (is.null(vg)) return(df)
	params = names(vg$params)
	vars = setdiff(vg$vars,params)
	ind.col = first.non.null(intersect("eqo.ind",colnames(df)),"eq.ind")
	if (length(unique(df$variant))>1) ind.col = c("variant",ind.col)

	cols = unique(c(ind.col, vars, paste0("payoff_",1:5), paste0("util_",1:5), params, colnames(df)))
	cols = intersect(cols, colnames(df))

	ord = try(do.call(order,df[,cols]))
	if (is(ord,"try-error")) return(df[,cols])
	df[ord,cols]
}

get.gambit.solver = function(solver=NULL, mixed=FALSE, just.spe=TRUE, solvemode=NULL) {
	if (!is.null(solver)) {
		return(solver)
	}

  if (is.null(solver)) {
    if (!mixed) {
      solver = "gambit-enumpure -q"
      if (just.spe) {
        solver = paste0(solver," -P")
      }
    } else {
      solver = "gambit-logit -q -e"
    }
  }
	solver

}


gambit.output.to.eq.li = function(txt,tg) {
  restore.point("gambit.output.to.eq.li")

  # no equilibrium found
  if (length(txt)==0)
    return(NULL)

  # in large games, equilibria may be longer than one line
  txt = merge.lines(txt)
  txt = sep.lines(txt,"NE,")[-1]



  # compact equilibirum representation
  # One equilibrium is just a vector that first contains for each
  # information set move the probability that it ocurs
  # afterwards, we also have the probability of moves of nature
  # ordered like .info.set.move.ind
  ceq.li = lapply(strsplit(txt,",",fixed=TRUE), function(vec) as.numeric(vec))


  # We have to inject these probabilties in our equilibrium template
  # tg$et.mat to generate an equilibrium data.frame eq.df
  # eq.mat will have the same dimensions than oco.df
  # each cell describes the probability that the particluar move
  # takes place:
  # (eq. prob for actions, prob for move of nature, 1 for transformations)
  # rowSums(eq.mat) then give the probability distribution over outcomes
  # for a given equilibrium.

  # et.ind are the indices of et.mat
  # that denote information sets
  et.ind = which(tg$et.mat<0)
  i = 1
  eq.li = lapply(seq_along(ceq.li), function(i) {
  	ceq.to.eq.mat(ceq = ceq.li[[i]],eq.ind=i, et.ind=et.ind, tg=tg)
  })


  eq.li

}


# Just found out recently that
# Gambit equilibrium output is sorted by player
# first and then by order in the efg file using depth first
# traversel.
#
# In contrast, gtree inform sets are numbered by stages
# and breadth first.
#
# The following function maps gtree .info.set.move indices
# to the position of the move in the Gambit equilibrium output
compute.efg.move.inds = function(tg,efg.txt = readLines(efg.file), efg.file=file.path(get.efg.dir(tg$gameId), tg.efg.file.name(tg))) {
  restore.point("efg.move.inds")

  rows = str.starts.with(efg.txt, "p ")
  efg.txt = str.between(efg.txt[rows],'" ',' "')
  player = as.integer(str.left.of(efg.txt," "))
  info.set.ind = as.integer(str.right.of(efg.txt," "))

  df = as_data_frame(nlist(player, info.set.ind))

  # Only first encounter of an information set is relevant
  # for gambit's output order
  df = df[!duplicated(info.set.ind),]
  df$efg.pos = seq_len(NROW(df))
  ord = order(df$player, df$efg.pos)
  df = df[ord,]
  df$efg.pos = seq_len(NROW(df))

  ise.df = tg$ise.df
  info.set.ind = 1
  efg.move.inds = c(unlist(lapply(df$info.set.ind, function(info.set.ind){
    row = which(ise.df$.info.set.ind == info.set.ind)
    start = ise.df$.info.set.move.ind.start[row]
    start:(start+ise.df$.num.moves[row]-1)
  })))

  efg.move.inds
  # Example:
  # efg.move.inds
  # [1]  1  2  3  4  7  8  9  5  6 10 11 12 13 14 15
  # This means ceq[5] should be set where tg$et.mat == -7
  # Let us define ceq.move.order with
  #   ceq.move.order[7] = ceq[5]
  # We thus need
  #   ceq.move.order[efg.move.inds] = ceq
  #

  # We have
  # ceq.move.order = ceq
  # ceq.move.order[efg.move.inds] = ceq
  # We have ceq[efg.move.inds]

}


